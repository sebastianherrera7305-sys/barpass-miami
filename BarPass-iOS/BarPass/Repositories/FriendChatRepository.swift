import Foundation

/// Direct 1:1 chat between two accepted friends.
///
/// Same architecture as the chapter chat, not a second weaker one:
/// messages are encrypted at rest with a key that lives in Supabase Vault
/// and never reaches this binary, reads and writes go through SECURITY
/// DEFINER RPCs, and rate limiting, block enforcement and reporting are
/// all server-side. This client never decides who may message whom — it
/// cannot, because the raw `friend_messages` table has no client grant at
/// all and its content column is opaque bytea.
protocol FriendChatRepository: Sendable {
    /// The inbox: one row per thread with a current friend, newest first.
    func threads() async throws -> [FriendThreadSummary]
    /// Reading also marks the thread read, server-side.
    func messages(with userId: String, limit: Int) async throws -> [FriendMessage]
    func send(to userId: String, text: String) async throws
    func report(messageId: String, reason: String) async throws
}

final actor SupabaseFriendChatRepository: FriendChatRepository {

    func threads() async throws -> [FriendThreadSummary] {
        let data = try await callRPC("list_friend_threads", rawBody: Data("{}".utf8))
        return try SupabaseRESTClient.decoder.decode([FriendThreadSummary].self, from: data)
    }

    /// An empty result is the correct answer for "we are no longer
    /// friends" and for "one of us blocked the other" — the RPC returns
    /// zero rows rather than an error in both cases, so a blocked user
    /// cannot tell the two apart by watching the failure mode.
    func messages(with userId: String, limit: Int = 200) async throws -> [FriendMessage] {
        let body = try JSONSerialization.data(withJSONObject: [
            "p_user_id": userId,
            "p_limit": limit,
        ] as [String: Any])
        let data = try await callRPC("get_friend_messages", rawBody: body)
        return try SupabaseRESTClient.decoder.decode([FriendMessage].self, from: data)
    }

    /// Friendship and blocks are re-checked by the RPC on every send, not
    /// only when the thread was created: an open thread has to go silent
    /// the moment either side blocks or unfriends.
    func send(to userId: String, text: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "p_user_id": userId,
            "p_text": text,
        ])
        _ = try await callRPC("send_friend_message", rawBody: body)
    }

    /// In a chapter (many participants) auto-hide needed three
    /// independent reports. A 1:1 thread has exactly one person who can
    /// legitimately report, so one report from the recipient hides the
    /// message immediately — the server enforces that, and that a sender
    /// cannot report their own message.
    func report(messageId: String, reason: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "p_message_id": messageId,
            "p_reason": reason,
        ])
        _ = try await callRPC("report_friend_message", rawBody: body)
    }

    private func callRPC(_ name: String, rawBody: Data) async throws -> Data {
        let session = try await SupabaseRESTClient.freshSession()
        let request = try SupabaseRESTClient.request(
            "POST", path: "rpc/\(name)", body: rawBody, accessToken: session.accessToken
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FriendError.unknown }
        guard 200..<300 ~= http.statusCode else {
            throw FriendError.from(responseBody: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }
}
