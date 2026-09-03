import Foundation

struct ChapterMessage: Codable, Identifiable, Sendable {
    let id: String
    let chapterId: String
    let userId: String?
    let text: String
    let createdAt: Date
    let isSystem: Bool
}

protocol ChapterChatRepository: Sendable {
    func messages(chapterId: String) async throws -> [ChapterMessage]
    func send(text: String) async throws
    func report(messageId: String, reason: String) async throws
}

final actor SupabaseChapterChatRepository: ChapterChatRepository {
    /// Message content is encrypted at rest (see chapter_chat_encryption.sql)
    /// — the raw `chapter_messages` table only has ciphertext to offer, so
    /// reads go through the decrypting RPC instead of a plain REST GET.
    /// `chapterId` is accepted for API compatibility but unused: the RPC
    /// derives the caller's chapter server-side from their own affiliation,
    /// the same way send_chapter_message() always has.
    func messages(chapterId: String) async throws -> [ChapterMessage] {
        let session = try await SupabaseRESTClient.freshSession()
        let request = try SupabaseRESTClient.request(
            "POST", path: "rpc/get_chapter_messages", body: Data("{}".utf8), accessToken: session.accessToken
        )
        let data = try await SupabaseRESTClient.send(request)
        return try SupabaseRESTClient.decoder.decode([ChapterMessage].self, from: data)
    }

    /// RPC enforces affiliation + ban + rate limit server-side — the client
    /// never decides which chapter it's posting to.
    func send(text: String) async throws {
        let session = try await SupabaseRESTClient.freshSession()
        let body = try SupabaseRESTClient.encoder.encode(["p_text": text])
        let request = try SupabaseRESTClient.request(
            "POST", path: "rpc/send_chapter_message", body: body, accessToken: session.accessToken
        )
        do {
            try await SupabaseRESTClient.send(request)
        } catch {
            throw NSError(domain: "ChapterChat", code: 0, userInfo: [NSLocalizedDescriptionKey: error.localizedDescription])
        }
    }

    func report(messageId: String, reason: String) async throws {
        let session = try await SupabaseRESTClient.freshSession()
        let body = try SupabaseRESTClient.encoder.encode(["p_message_id": messageId, "p_reason": reason])
        let request = try SupabaseRESTClient.request(
            "POST", path: "rpc/report_chapter_message", body: body, accessToken: session.accessToken
        )
        try await SupabaseRESTClient.send(request)
    }
}
