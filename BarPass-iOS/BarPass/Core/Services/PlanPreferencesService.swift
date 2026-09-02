import Foundation

/// Lightweight cross-conversation memory — the actual, felt difference
/// between Free and Premium (Fase 4 real, 2026-09-02), not just a higher
/// usage cap. 05_PREMIUM_AI_SPEC.md: "Memory: Start lightweight... Do not
/// build a complicated memory system in V1" — this stores exactly one
/// thing, the `TripContext` (vibe/company/inclusive prefs/prompt) from the
/// last plan-generating turn, and only for Premium users.
///
/// `PlanView` reads this once when a fresh conversation starts (Premium
/// only) to pre-fill the context picker chips with what the user picked
/// last time, and writes it after every Premium plan-generating turn. Free
/// never calls this at all — every new conversation for Free starts blank,
/// by design.
actor PlanPreferencesService {
    static let shared = PlanPreferencesService()

    private struct Row: Codable {
        let userId: String
        let context: TripContext

        enum CodingKeys: String, CodingKey {
            case context
            case userId = "user_id"
        }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// `nil` on any failure (no session, no saved row yet, network hiccup)
    /// — this is a nice-to-have personalization touch, never something
    /// that should block or error out the chat.
    func load() async -> TripContext? {
        do {
            let session = try await SupabaseRESTClient.freshSession()
            let req = try SupabaseRESTClient.request(
                "GET", path: "plan_preferences",
                queryItems: [
                    URLQueryItem(name: "select", value: "context"),
                    URLQueryItem(name: "user_id", value: "eq.\(session.user.id)"),
                ],
                accessToken: session.accessToken
            )
            let data = try await SupabaseRESTClient.send(req)
            struct ContextOnly: Decodable { let context: TripContext }
            return try Self.decoder.decode([ContextOnly].self, from: data).first?.context
        } catch {
            return nil
        }
    }

    /// Upsert by user id — best-effort, silent on failure (same reasoning
    /// as `load()`).
    func save(_ context: TripContext) async {
        do {
            let session = try await SupabaseRESTClient.freshSession()
            let row = Row(userId: session.user.id, context: context)
            let body = try Self.encoder.encode(row)
            let req = try SupabaseRESTClient.request(
                "POST", path: "plan_preferences", body: body, accessToken: session.accessToken,
                extraHeaders: ["Prefer": "return=minimal,resolution=merge-duplicates"]
            )
            _ = try await SupabaseRESTClient.send(req)
        } catch {
            // Best-effort — see load()'s doc comment.
        }
    }

    /// A short, human-readable summary of `context` for the AI prompt's
    /// `rememberedVibe` — e.g. "nightlife, with friends, mid-range budget".
    /// Built here (not in `PlanEngine`) so the "what counts as memorable"
    /// logic lives next to the storage it's derived from.
    @MainActor
    func summarize(_ context: TripContext) -> String {
        let l10n = L10n.shared
        var parts: [String] = []
        for id in context.intents.prefix(2) {
            if let intent = ExperienceIntent(rawValue: id) { parts.append(l10n.t(intent.labelKey)) }
        }
        if let company = context.company { parts.append(l10n.t(company.labelKey)) }
        return parts.joined(separator: ", ")
    }
}
