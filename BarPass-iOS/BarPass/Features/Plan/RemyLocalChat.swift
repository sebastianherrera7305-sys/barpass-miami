import Foundation

/// Lightweight, instant, on-device "small talk" for the Plan chat. Every
/// call to the real Remy (barpass-v2's /api/concierge, an NVIDIA-hosted
/// reasoning model) takes 20-30s+ — fine for the one moment that matters
/// (building the actual plan), but firing it on every single chat turn made
/// ordinary back-and-forth ("$50 tonight" / "chill vibe") feel broken. This
/// engine handles everything BEFORE the user actually wants a plan: reading
/// out what it's picked up, asking one clarifying question if there's
/// nothing to go on yet, and knowing when to offer the real build step.
/// The real API is only ever called once the user acts on that offer.
enum RemyLocalChat {
    struct Reply {
        /// Localized text to show immediately, no network involved.
        let text: String
        /// True when there's enough signal to offer building a real plan —
        /// the UI shows a "Build my plan" action under this message.
        let offerBuild: Bool
    }

    private static let affirmativeWords: Set<String> = [
        "si", "sí", "dale", "yes", "yeah", "yep", "sure", "ok", "okay", "vamos",
        "hazlo", "armalo", "ármalo", "build", "please", "claro", "va", "porfa",
        "sim", "bora", "faz", "manda",
    ]
    private static let negativeWords: Set<String> = [
        "no", "nah", "espera", "wait", "todavia", "todavía", "not yet", "ainda",
    ]

    /// True when the user's message is a plain "yes, go ahead" — only
    /// meaningful right after `Reply.offerBuild` was shown.
    static func isAffirmative(_ text: String) -> Bool {
        let words = Set(text.lowercased().split { !$0.isLetter }.map(String.init))
        if !words.isDisjoint(with: negativeWords) { return false }
        return !words.isDisjoint(with: affirmativeWords)
    }

    /// Very small signal extraction — just enough to (a) decide whether
    /// there's something to build a plan around and (b) echo it back so the
    /// reply doesn't feel like a form. Real understanding of the request
    /// happens later, in the actual model call.
    private static func hasSignal(_ context: String) -> Bool {
        let text = context.lowercased()
        if text.range(of: #"\$?\s*\d{2,4}"#, options: .regularExpression) != nil { return true }
        let vibeWords = [
            "party", "fiesta", "chill", "relax", "date", "cita", "rooftop",
            "upscale", "elegante", "birthday", "cumple", "salsa", "house",
            "techno", "reggaeton", "reggaetón", "hip hop", "cover", "brickell",
            "wynwood", "beach", "playa", "girls night", "noche de chicas",
            "bachelor", "despedida", "live music", "música en vivo",
        ]
        return vibeWords.contains { text.contains($0) }
    }

    /// Generic, venue-agnostic questions — how the app works, general
    /// entry policy — answered instantly and definitively, no API call.
    /// Deliberately does NOT cover venue-specific facts (a dress code, a
    /// cover charge, hours for one named place): those aren't knowable
    /// without a real, current source, and a hardcoded guess here would be
    /// exactly the fabricated-data problem this app spent months fixing in
    /// its venue catalog (see CLAUDE.md's venue data provenance notes) —
    /// venue-specific questions fall through to the real plan flow, which
    /// reads the live catalog.
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
    /// — checked before anything else, so these never wait on a plan flow
    /// or a network call.
    static func matchFAQ(_ text: String) -> String? {
        let lower = text.lowercased()
        for entry in faqEntries where entry.keywords.contains(where: { lower.contains($0) }) {
            return L10n.tSync(entry.key)
        }
        return nil
    }

    /// `context` is every user message so far in this conversation, joined —
    /// the same rolling signal the old single-shot prompt used to build
    /// from, just accumulated turn by turn now instead of typed all at once.
    static func reply(context: String, turnIndex: Int) -> Reply {
        if hasSignal(context) {
            let variant = turnIndex % 2
            return Reply(text: L10n.tSync("plan.chat.native.confirm.\(variant)"), offerBuild: true)
        }
        let variant = turnIndex % 2
        return Reply(text: L10n.tSync("plan.chat.native.ask.\(variant)"), offerBuild: false)
    }

    static var buildingMessage: String {
        L10n.tSync("plan.chat.native.building.0")
    }
}
