import Foundation
import CoreLocation

/// Turns one user turn into Remy's reply — the orchestration layer between
/// `PlanView` and the two generation engines (`APIClient.fetchConciergePlan`,
/// `NightPlan.local`). Provider-agnostic by design (03_CHAT_ENGINE.md's
/// "critical rule": the UI shouldn't care whether a response came from the
/// AI concierge or the local fallback) — `PlanView` only ever sees a
/// `PlanMessage` back.
enum PlanEngine {
    /// Refinement quick actions shown under a generated plan — tapping one
    /// re-generates against the SAME conversation instead of starting over.
    /// Labels are l10n keys; `hint` is the (English, matching venue tag/
    /// keyword data) text actually fed to the generation engines — same
    /// split `PlanView` already used for suggestion chips vs. their
    /// underlying prompt.
    ///
    /// `priceRange`/`budgetHint` (2026-09-02 bug fix): "Cheaper"/"More
    /// upscale" used to be pure free text, with no guaranteed effect on
    /// price — neither `ExperienceScorer` nor the AI request carried any
    /// structured price signal, so the button could silently do nothing.
    /// These now feed `NightPlan.local`'s hard `priceRange` filter and
    /// `APIClient.fetchConciergePlan`'s `budget` param, same mechanism the
    /// context picker's budget chips use (`PlanBudgetOption`, PlanView.swift).
    struct RefinementAction {
        let labelKey: String
        let hint: String
        let priceRange: ClosedRange<Int>?
        let budgetHint: Double?
    }
    static let refinementActions: [RefinementAction] = [
        RefinementAction(labelKey: "plan.action.upscale", hint: "more upscale and exclusive", priceRange: 3...4, budgetHint: 175),
        RefinementAction(labelKey: "plan.action.cheaper", hint: "more affordable, lower budget", priceRange: 1...2, budgetHint: 35),
        RefinementAction(labelKey: "plan.action.closer",  hint: "closer to my current location", priceRange: nil, budgetHint: nil),
        RefinementAction(labelKey: "plan.action.social",  hint: "more social and lively, good for meeting people", priceRange: nil, budgetHint: nil),
    ]

    /// Generates the next plan for this turn — concierge first, local
    /// fallback on any failure — and wraps it as Remy's reply. Never
    /// throws: a total failure (no venues, empty catalog) still comes back
    /// as a message, just with an empty plan (`NightPlanView` already
    /// renders that state).
    ///
    /// - Parameter priceRange: hard price-tier constraint (1...4, matching
    ///   `PriceTier.rawValue`) passed to `NightPlan.local` — from either
    ///   the context picker's budget chip or a refinement action.
    /// - Parameter budgetHint: representative dollar figure passed to the
    ///   AI concierge's `budget` param for the same constraint.
    /// - Parameter classifyIntent: runs `PlanIntentResolver` first (Phase 2,
    ///   08_DEVELOPER_TASKS.md) and returns a canned greeting/capability
    ///   reply instead of generating a plan when the text is clearly one of
    ///   those, not a planning request. `PlanView` passes `false` whenever
    ///   the turn came with structured signal (a context chip or a
    ///   refinement quick action) — those are unambiguous regardless of
    ///   their text, so classification would only risk a wrong call.
    static func respond(
        enginePrompt: String,
        conversation: PlanConversation,
        context: TripContext,
        venues: [BarPassVenue],
        userLocation: CLLocationCoordinate2D?,
        priceRange: ClosedRange<Int>? = nil,
        budgetHint: Double? = nil,
        classifyIntent: Bool = true
    ) async -> PlanMessage {
        if classifyIntent {
            switch PlanIntentResolver.resolve(enginePrompt) {
            case .greeting:
                return await MainActor.run {
                    PlanMessage(role: .assistant, text: L10n.shared.t("plan.block.greeting"), quickActions: quickSuggestions())
                }
            case .capability:
                return await MainActor.run {
                    PlanMessage(role: .assistant, text: L10n.shared.t("plan.block.capability"), quickActions: quickSuggestions())
                }
            case .planRequest:
                break // fall through to generation below
            }
        }

        // Every venue already shown anywhere in this conversation, not just
        // the latest plan (2026-09-02 bug fix) — otherwise refining twice
        // in a row ("Cheaper" then "Closer") could resurface a venue shown
        // two turns ago, since only a one-turn-deep exclusion window was
        // kept.
        let excludeSlugs = Array(Set(conversation.messages.flatMap { $0.plan?.stops.map(\.venueSlug) ?? [] }))

        let generated: NightPlan
        let source: PlanMessage.PlanSource
        do {
            generated = try await APIClient.fetchConciergePlan(prompt: enginePrompt, budget: budgetHint, excludeSlugs: excludeSlugs)
            source = .ai
        } catch {
            // AI unavailable (no server key, rate limited, offline, bad
            // response) — fall back silently. Never surface this raw to
            // the user (02_UX_ARCHITECTURE.md).
            generated = await NightPlan.local(prompt: enginePrompt, context: context, venues: venues, userLocation: userLocation, priceRange: priceRange)
            source = .local
        }

        let replyText = await MainActor.run { L10n.shared.t("plan.chat.hereYouGo") }
        let actions = await MainActor.run { refinementActions.map { L10n.shared.t($0.labelKey) } }
        return PlanMessage(role: .assistant, text: replyText, plan: generated, planSource: source, quickActions: actions)
    }

    /// The welcome message a fresh conversation starts with — onboarding
    /// suggestions as its quick actions (tapping one sends it as the first
    /// user turn), matching 02_UX_ARCHITECTURE.md's entry state.
    ///
    /// `greetingIndex` (0..<6) reuses the same rotating variants
    /// `PlanView`'s header title picks from (`plan.headerSubtitle.N` —
    /// "en qué te puedo ayudar hoy", "cómo hacemos tu noche mejor", etc.,
    /// TestFlight feedback via Sebastián/Opus 5) instead of a single fixed
    /// line, so the header and the first chat bubble read as the same
    /// greeting rather than two different ones.
    @MainActor
    static func welcomeMessage(greetingIndex: Int) -> PlanMessage {
        PlanMessage(role: .assistant, text: L10n.shared.t("plan.headerSubtitle.\(greetingIndex)"), quickActions: quickSuggestions())
    }

    /// Onboarding suggestion phrases — shared by the welcome message and
    /// the greeting/capability response blocks above, so a "hola" or "qué
    /// puedes hacer" reply still leaves the user with something tappable
    /// instead of a dead end.
    @MainActor
    private static func quickSuggestions() -> [String] {
        let l10n = L10n.shared
        return [
            l10n.t("plan.suggestion.budget"),
            l10n.t("plan.suggestion.friends"),
            l10n.t("plan.suggestion.dinnerClub"),
            l10n.t("plan.suggestion.houseMusic"),
            l10n.t("plan.suggestion.noCover"),
            l10n.t("plan.suggestion.birthday"),
            l10n.t("plan.suggestion.brickell"),
            l10n.t("plan.suggestion.different"),
        ]
    }
}
