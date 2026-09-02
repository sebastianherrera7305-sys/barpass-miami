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
    struct RefinementAction {
        let labelKey: String
        let hint: String
    }
    static let refinementActions: [RefinementAction] = [
        RefinementAction(labelKey: "plan.action.upscale", hint: "more upscale and exclusive"),
        RefinementAction(labelKey: "plan.action.cheaper", hint: "more affordable, lower budget"),
        RefinementAction(labelKey: "plan.action.closer",  hint: "closer to my current location"),
        RefinementAction(labelKey: "plan.action.social",  hint: "more social and lively, good for meeting people"),
    ]

    /// Generates the next plan for this turn — concierge first, local
    /// fallback on any failure — and wraps it as Remy's reply. Never
    /// throws: a total failure (no venues, empty catalog) still comes back
    /// as a message, just with an empty plan (`NightPlanView` already
    /// renders that state).
    static func respond(
        enginePrompt: String,
        conversation: PlanConversation,
        context: TripContext,
        venues: [BarPassVenue],
        userLocation: CLLocationCoordinate2D?
    ) async -> PlanMessage {
        let excludeSlugs = conversation.currentPlan?.stops.map(\.venueSlug) ?? []

        let generated: NightPlan
        do {
            generated = try await APIClient.fetchConciergePlan(prompt: enginePrompt, excludeSlugs: excludeSlugs)
        } catch {
            // AI unavailable (no server key, rate limited, offline, bad
            // response) — fall back silently. Never surface this raw to
            // the user (02_UX_ARCHITECTURE.md).
            generated = await NightPlan.local(prompt: enginePrompt, context: context, venues: venues, userLocation: userLocation)
        }

        let replyText = await MainActor.run { L10n.shared.t("plan.chat.hereYouGo") }
        let actions = await MainActor.run { refinementActions.map { L10n.shared.t($0.labelKey) } }
        return PlanMessage(role: .assistant, text: replyText, plan: generated, quickActions: actions)
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
        let l10n = L10n.shared
        let suggestions = [
            l10n.t("plan.suggestion.budget"),
            l10n.t("plan.suggestion.friends"),
            l10n.t("plan.suggestion.dinnerClub"),
            l10n.t("plan.suggestion.houseMusic"),
            l10n.t("plan.suggestion.noCover"),
            l10n.t("plan.suggestion.birthday"),
            l10n.t("plan.suggestion.brickell"),
            l10n.t("plan.suggestion.different"),
        ]
        return PlanMessage(role: .assistant, text: l10n.t("plan.headerSubtitle.\(greetingIndex)"), quickActions: suggestions)
    }
}
