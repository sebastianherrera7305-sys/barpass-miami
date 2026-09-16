import Foundation

/// Lightweight cross-conversation memory — the actual, felt difference
/// between Free and Premium beyond the usage cap (05_PREMIUM_AI_SPEC.md:
/// "Start lightweight... Do not build a complicated memory system in V1").
///
/// Plan is a pure chat now (no context-picker chips/structured trip state),
/// so what's remembered is just a short, human-readable line distilled from
/// the last plan Remy built — e.g. "The Brickell Golden Hour: rooftop
/// sunset drinks, then a late club". `PlanView` sends this as
/// `rememberedVibe` on every turn of a Premium user's new conversation, so
/// Remy already has a sense of their taste before they've said a word this
/// time. Free never writes or reads this at all — every new conversation
/// starts blank, by design.
actor PlanPreferencesService {
    static let shared = PlanPreferencesService()

    private struct Row: Codable {
        let userId: String
        let context: Context
        struct Context: Codable { let summary: String }

        enum CodingKeys: String, CodingKey {
            case context
            case userId = "user_id"
        }
    }

    /// `nil` on any failure (no session, nothing saved yet, network hiccup)
    /// — this is a nice-to-have personalization touch, never something that
    /// should block or error out the chat.
    func load() async -> String? {
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
            struct ContextOnly: Decodable { let context: Row.Context }
            let summary = try JSONDecoder().decode([ContextOnly].self, from: data).first?.context.summary
            return (summary?.isEmpty ?? true) ? nil : summary
        } catch {
            return nil
        }
    }

    /// Upsert by user id — best-effort, silent on failure (same reasoning
    /// as `load()`).
    func save(summary: String) async {
        guard !summary.isEmpty else { return }
        do {
            let session = try await SupabaseRESTClient.freshSession()
            let row = Row(userId: session.user.id, context: .init(summary: summary))
            let body = try JSONEncoder().encode(row)
            let req = try SupabaseRESTClient.request(
                "POST", path: "plan_preferences", body: body, accessToken: session.accessToken,
                extraHeaders: ["Prefer": "return=minimal,resolution=merge-duplicates"]
            )
            _ = try await SupabaseRESTClient.send(req)
        } catch {
            // Best-effort — see load()'s doc comment.
        }
    }
}
