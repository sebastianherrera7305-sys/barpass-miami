import Foundation

struct ChapterMember: Codable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let bpxPoints: Int
    let joinedAt: Date
}

protocol ChapterMembersRepository: Sendable {
    /// Server-side scoped to the caller's own chapter_id (same affiliation +
    /// ban gate as chat/events) — never a client-supplied chapter filter.
    func members() async throws -> [ChapterMember]
}

final actor SupabaseChapterMembersRepository: ChapterMembersRepository {
    func members() async throws -> [ChapterMember] {
        let session = try await SupabaseRESTClient.freshSession()
        let request = try SupabaseRESTClient.request(
            "POST", path: "rpc/list_chapter_members", body: Data("{}".utf8), accessToken: session.accessToken
        )
        let data = try await SupabaseRESTClient.send(request)
        return try SupabaseRESTClient.decoder.decode([ChapterMember].self, from: data)
    }
}
