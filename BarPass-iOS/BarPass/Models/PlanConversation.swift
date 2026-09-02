import Foundation

// MARK: - Plan chat (Phase 1 — see CLAUDE.md → "Plan Chat Architecture")
//
// Multi-turn conversation model for the Plan tab. A message is either the
// user's own text, or Remy's reply — which may carry a generated `NightPlan`
// (rendered inline as a card) and/or `quickActions` (tappable follow-up
// phrases: onboarding suggestions on the welcome message, refinement
// actions — "more upscale", "cheaper" — on a plan message). One shared
// shape for both roles, matching 03_CHAT_ENGINE.md's response contract
// (`message, cards, quickActions, plan`) — `cards` is just `plan.stops`
// today since Plan has no other card type yet.

struct PlanMessage: Identifiable, Codable, Hashable {
    enum Role: String, Codable {
        case user
        case assistant
    }

    /// Which engine produced `plan` — `nil` when there's no plan on this
    /// message. Gates the scenePhase "refresh real-time badges" pass in
    /// `PlanView` (2026-09-02 bug fix): that pass must only ever re-run the
    /// *local* engine, never silently replace an AI-concierge plan with a
    /// different, locally-scored one.
    enum PlanSource: String, Codable {
        case ai
        case local
    }

    var id: String = UUID().uuidString
    var role: Role
    var text: String
    var plan: NightPlan? = nil
    var planSource: PlanSource? = nil
    var quickActions: [String] = []
    var createdAt: Date = .now
}

struct PlanConversation: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var title: String = ""
    var messages: [PlanMessage] = []
    /// The vibe/company/inclusive-pref/free-text context that produced the
    /// most recent plan — persisted with the conversation (instead of
    /// living in `PlanView`'s own `@State`, 2026-09-02 bug fix) so it
    /// survives switching conversations from History, app restart, and the
    /// Supabase round-trip instead of silently going stale or leaking from
    /// a previously-viewed conversation.
    var lastContext: TripContext = TripContext()
    var createdAt: Date = .now
    var updatedAt: Date = .now

    /// The plan currently "live" in this conversation — derived from the
    /// most recent message that carries one. Deliberately NOT a stored
    /// property (2026-09-02 bug fix): it used to be, and had to be written
    /// by hand in two places on every update (`PlanView.sendMessage` and
    /// the scenePhase refresh), which could — and did — drift out of sync
    /// with what the transcript actually shows. Deriving it makes that
    /// class of bug structurally impossible.
    var currentPlan: NightPlan? {
        messages.last(where: { $0.plan != nil })?.plan
    }

    /// True only when the live plan came from the local fallback engine —
    /// see `PlanMessage.PlanSource`.
    var currentPlanIsLocalFallback: Bool {
        messages.last(where: { $0.plan != nil })?.planSource == .local
    }

    /// A short label for conversation-history lists — the first thing the
    /// user actually said, falling back to the plan's own title once one
    /// exists, so a chip-only turn (no typed text) still gets a real label.
    var displayTitle: String {
        if !title.isEmpty { return title }
        return messages.first(where: { $0.role == .user })?.text
            ?? currentPlan?.title
            ?? ""
    }
}
