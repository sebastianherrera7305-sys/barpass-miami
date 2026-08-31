import Foundation

/// The signed-in user's self-declared affiliation (university + Greek
/// chapter). Self-declared, not verified — anyone can pick any chapter from
/// the directory, we don't check real-world membership.
struct ProfileAffiliation: Codable, Sendable {
    let universityId: String?
    let chapterId: String?
}

protocol ProfileAffiliationRepository: Sendable {
    func getAffiliation() async throws -> ProfileAffiliation
    func setAffiliation(universityId: String?, chapterId: String?) async throws
}

final actor SupabaseProfileAffiliationRepository: ProfileAffiliationRepository {
    func getAffiliation() async throws -> ProfileAffiliation {
        let session = try await SupabaseRESTClient.freshSession()
        let request = try SupabaseRESTClient.request(
            "GET", path: "profiles",
            queryItems: [
                URLQueryItem(name: "select", value: "university_id,chapter_id"),
                URLQueryItem(name: "id", value: "eq.\(session.user.id)"),
            ],
            accessToken: session.accessToken
        )
        let data = try await SupabaseRESTClient.send(request)
        let rows = try SupabaseRESTClient.decoder.decode([ProfileAffiliation].self, from: data)
        return rows.first ?? ProfileAffiliation(universityId: nil, chapterId: nil)
    }

    func setAffiliation(universityId: String?, chapterId: String?) async throws {
        let session = try await SupabaseRESTClient.freshSession()
        struct Body: Encodable {
            let university_id: String?
            let chapter_id: String?
        }
        let body = try SupabaseRESTClient.encoder.encode(Body(university_id: universityId, chapter_id: chapterId))
        let request = try SupabaseRESTClient.request(
            "PATCH", path: "profiles",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(session.user.id)")],
            body: body, accessToken: session.accessToken,
            extraHeaders: ["Prefer": "return=minimal"]
        )
        try await SupabaseRESTClient.send(request)
    }
}
