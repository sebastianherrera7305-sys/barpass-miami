import Foundation

/// Classifies a free-typed message before generation — 03_CHAT_ENGINE.md's
/// "Intent + Context Layer" (Phase 2, 08_DEVELOPER_TASKS.md: "Implement
/// intent resolver").
///
/// Deliberately narrow: only intercepts CLEAR greetings and capability
/// questions with a small canned reply. Everything else — even vague or
/// terse text — still attempts a plan, because 02_UX_ARCHITECTURE.md
/// explicitly warns against turning Free into a questionnaire ("Avoid
/// asking 7–10 questions before giving value"), and a wrong "let me ask a
/// clarifying question" guess is more annoying than a so-so plan attempt.
///
/// Only runs for pure free-text turns — `PlanView` skips it entirely
/// whenever the user picked context chips or tapped a refinement quick
/// action, since those are already unambiguous plan requests regardless of
/// what text (if any) came with them.
enum PlanIntent {
    case planRequest
    case greeting
    case capability
}

enum PlanIntentResolver {
    /// A message that, once trimmed of punctuation, is ENTIRELY one of
    /// these (or these plus one more short word, e.g. "hola!" / "hey remy")
    /// is a greeting — "hola" counts, "hola quiero algo cerca de brickell"
    /// doesn't (real planning content after the greeting).
    private static let greetingWords: Set<String> = [
        "hola", "holaa", "holis", "buenas", "buenass",
        "hey", "hi", "hello", "yo", "sup",
        "oi", "ola", "olá", "e ai", "eae",
        "gracias", "thanks", "thank you", "obrigado", "obrigada",
        "remy",
    ]

    private static let capabilityPhrases: [String] = [
        "que puedes hacer", "qué puedes hacer", "que sabes hacer", "qué sabes hacer",
        "que haces", "qué haces", "como funciona", "cómo funciona esto",
        "quien eres", "quién eres", "que eres", "qué eres",
        "what can you do", "what do you do", "how does this work", "how do you work",
        "who are you", "what are you",
        "o que você faz", "o que voce faz", "o que você pode fazer",
        "como funciona isso", "quem é você", "quem e voce",
    ]

    static func resolve(_ text: String) -> PlanIntent {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return .planRequest }

        let stripped = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "!¡.,¿?; "))
        let words = stripped.split(separator: " ").map(String.init)

        if words.count <= 2, words.allSatisfy({ greetingWords.contains($0) || $0 == "remy" }) {
            return .greeting
        }

        if capabilityPhrases.contains(where: normalized.contains) {
            return .capability
        }

        return .planRequest
    }
}
