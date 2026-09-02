import Foundation

/// Real Supabase-backed Plan conversations (`public.plan_conversations`,
/// see barpass-v2/supabase/schema.sql). Same shape as `SupabasePlanRepository`
/// for `night_plans`: the whole `PlanConversation` — including every
/// message — is stored as one jsonb blob in the `conversation` column,
/// with `id`/`user_id`/`title` as their own columns purely for RLS and
/// future listing/search.
///
/// Requires a real signed-in session — RLS scopes every row to
/// `auth.uid()`, so guest mode (no session) can't read/write conversations
/// at all, same restriction `SupabasePlanRepository`/`SupabaseTripRepository`
/// have. `PlanView` degrades to `LocalConversationRepository` for guests.
actor SupabaseConversationRepository: ConversationRepository {
    struct NoSessionError: LocalizedError {
        var errorDescription: String? { L10n.tSync("plan.error.noSession") }
    }

    private struct Row: Codable {
        let id: String
        let userId: String
        let title: String
        let conversation: PlanConversation

        enum CodingKeys: String, CodingKey {
            case id, title, conversation
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

    private func session() throws -> AuthSession {
        guard let s = AuthService.shared.restoreSession() else { throw NoSessionError() }
        return s
    }

    private func request(_ method: String, path: String, body: Data? = nil) throws -> URLRequest {
        try SupabaseRESTClient.request(method, path: path, body: body, accessToken: try session().accessToken)
    }

    // MARK: - ConversationRepository

    func getConversations() async throws -> [PlanConversation] {
        let req = try request("GET", path: "plan_conversations?select=id,user_id,title,conversation&order=updated_at.desc")
        let data = try await SupabaseRESTClient.send(req)
        let rows = try Self.decoder.decode([Row].self, from: data)
        return rows.map(\.conversation)
    }

    /// Upsert by id — same overwrite-or-insert semantics as
    /// `SupabasePlanRepository.savePlan`, called again after every turn so
    /// the whole conversation (including the new message) stays current.
    func saveConversation(_ conversation: PlanConversation) async throws {
        let userId = try session().user.id
        var conversation = conversation
        conversation.updatedAt = .now
        let row = Row(id: conversation.id, userId: userId, title: conversation.displayTitle, conversation: conversation)
        let body = try Self.encoder.encode(row)
        let req = try SupabaseRESTClient.request(
            "POST", path: "plan_conversations", body: body, accessToken: try session().accessToken,
            extraHeaders: ["Prefer": "return=minimal,resolution=merge-duplicates"]
        )
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? "save failed"])
        }
    }

    func deleteConversation(_ conversation: PlanConversation) async throws {
        let req = try request("DELETE", path: "plan_conversations?id=eq.\(conversation.id)")
        try await SupabaseRESTClient.send(req)
    }
}
