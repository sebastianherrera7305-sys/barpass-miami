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

    var id: String = UUID().uuidString
    var role: Role
    var text: String
    var plan: NightPlan? = nil
    var quickActions: [String] = []
    var createdAt: Date = .now
}

struct PlanConversation: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var title: String = ""
    var messages: [PlanMessage] = []
    /// The plan currently being iterated on — refinement quick actions act
    /// on this. Distinct from any older plan earlier in `messages`: only
    /// the latest one is "live".
    var currentPlan: NightPlan? = nil
    var createdAt: Date = .now
    var updatedAt: Date = .now

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
