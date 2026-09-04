import Foundation

/// Instant, on-device helpers for the Plan chat that genuinely don't need
/// the real Remy — generic app/policy FAQs and language detection. Every
/// other turn goes straight to the real AI (barpass-v2's /api/concierge,
/// Groq, ~120ms to first token) with the full conversation history; it
/// already knows how to ask one contextual follow-up or recommend real
/// venues per its own system prompt (concierge-prompt.ts).
///
/// This used to also own a canned "ask for budget/vibe, then wait for an
/// explicit yes" layer that gated the real AI behind a keyword match on a
/// short fixed word list. TestFlight, 2026-09-05: real context the user
/// actually gave ("mi amiga es mexicana y viene a Miami") hit none of
/// those keywords, so the user got the same generic "give me a budget or
/// vibe" question forever — and the real AI, with its actually-contextual
/// system prompt, was never even called. Removed rather than patched
/// again: reading the conversation and asking a smart follow-up is exactly
/// what the real model is for, not something a keyword list can fake.
enum RemyLocalChat {
    /// Generic, venue-agnostic questions — how the app works, general
    /// entry policy — answered instantly and definitively, no API call.
    /// Deliberately does NOT cover venue-specific facts (a dress code, a
    /// cover charge, hours for one named place): those aren't knowable
    /// without a real, current source, and a hardcoded guess here would be
    /// exactly the fabricated-data problem this app spent months fixing in
    /// its venue catalog (see CLAUDE.md's venue data provenance notes) —
    /// venue-specific questions fall through to the real AI, which reads
    /// the live catalog.
    private struct FAQEntry {
        let keywords: [String]
        let key: String
    }
    private static let faqEntries: [FAQEntry] = [
        FAQEntry(keywords: ["book", "reservar", "reserve", "booking", "mesa a través", "how do i book"], key: "plan.chat.faq.bookTable"),
        FAQEntry(keywords: ["cancel", "cancelar"], key: "plan.chat.faq.cancelReservation"),
        FAQEntry(keywords: ["age requirement", "how old", "edad", "idade", "21+", "18+"], key: "plan.chat.faq.ageRequirement"),
        FAQEntry(keywords: ["dress code", "código de vest", "código de vestimenta", "what to wear", "que ponerme", "qué ponerme"], key: "plan.chat.faq.dressCode"),
        FAQEntry(keywords: ["how much is cover", "cover charge", "precio de entrada", "cuanto es la entrada", "cuánto es la entrada", "preço da entrada"], key: "plan.chat.faq.coverCharge"),
        FAQEntry(keywords: ["guest list", "lista de invitados", "lista de convidados"], key: "plan.chat.faq.guestList"),
        FAQEntry(keywords: ["parking", "valet", "estacionamiento", "estacionamento", "parqueo"], key: "plan.chat.faq.parking"),
    ]

    /// Returns a definitive, generic answer for common app/policy questions
    /// — checked before anything else, so these never wait on a network call.
    static func matchFAQ(_ text: String, language: AppLanguage) -> String? {
        let lower = text.lowercased()
        for entry in faqEntries where entry.keywords.contains(where: { lower.contains($0) }) {
            return L10n.t(entry.key, language: language)
        }
        return nil
    }

    /// Detects which of the app's 3 supported languages a single message is
    /// written in — mirrors the "reply in the user's language" rule already
    /// in Remy's real AI system prompt, but usable client-side before that
    /// call returns (e.g. to answer an FAQ in the right language instantly).
    /// Character- and word-level markers, not a real classifier — good
    /// enough for short chat messages, and errs toward `fallback` (the
    /// app's current language) when a message is too short/ambiguous to
    /// tell (e.g. "$50", "yes").
    static func detectLanguage(_ text: String, fallback: AppLanguage) -> AppLanguage {
        let lower = text.lowercased()

        // Strong, unambiguous markers first — a single hit is enough.
        if lower.contains(where: { "ãõ".contains($0) }) { return .pt }
        if lower.contains(where: { "ñ¿¡".contains($0) }) { return .es }

        let ptWords: Set<String> = ["não", "voce", "você", "então", "obrigado", "obrigada", "muito", "aqui", "coisa", "quero", "onde"]
        let esWords: Set<String> = ["qué", "que", "cómo", "como", "dónde", "donde", "quiero", "gracias", "más", "está", "aquí", "por favor"]
        let enWords: Set<String> = ["the", "you", "want", "please", "thanks", "where", "how", "what", "with", "for"]

        let tokens = Set(lower.split { !$0.isLetter }.map(String.init))
        let ptHits = tokens.intersection(ptWords).count
        let esHits = tokens.intersection(esWords).count
        let enHits = tokens.intersection(enWords).count

        let best = [(AppLanguage.pt, ptHits), (.es, esHits), (.en, enHits)].max { $0.1 < $1.1 }
        guard let best, best.1 > 0 else { return fallback }
        return best.0
    }
}
