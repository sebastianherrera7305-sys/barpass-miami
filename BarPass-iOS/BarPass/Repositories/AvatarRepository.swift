import Foundation

protocol AvatarRepository: Sendable {
    func getAvatarConfig() async throws -> AvatarConfig?
    func setAvatarConfig(_ config: AvatarConfig) async throws
    /// Switch back to initials/photo — a user who customized an avatar
    /// and changes their mind shouldn't be stuck with it.
    func clearAvatarConfig() async throws
}

/// Same pattern as `DisplayNameRepository`: `profiles.avatar_config` is
/// writable by its owner under the existing "update own profile" RLS
/// policy, no new column protection needed.
final actor SupabaseAvatarRepository: AvatarRepository {
    func getAvatarConfig() async throws -> AvatarConfig? {
        let session = try await SupabaseRESTClient.freshSession()
        let request = try SupabaseRESTClient.request(
            "GET", path: "profiles",
            queryItems: [
                URLQueryItem(name: "id", value: "eq.\(session.user.id)"),
                URLQueryItem(name: "select", value: "avatar_config"),
            ],
            accessToken: session.accessToken
        )
        let data = try await SupabaseRESTClient.send(request)
        struct Row: Decodable { let avatarConfig: AvatarConfig? }
        return try SupabaseRESTClient.decoder.decode([Row].self, from: data).first?.avatarConfig
    }

    func setAvatarConfig(_ config: AvatarConfig) async throws {
        let session = try await SupabaseRESTClient.freshSession()
        struct Body: Encodable { let avatar_config: AvatarConfig }
        let body = try SupabaseRESTClient.encoder.encode(Body(avatar_config: config))
        let request = try SupabaseRESTClient.request(
            "PATCH", path: "profiles",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(session.user.id)")],
            body: body, accessToken: session.accessToken,
            extraHeaders: ["Prefer": "return=minimal"]
        )
        try await SupabaseRESTClient.send(request)
    }

    func clearAvatarConfig() async throws {
        let session = try await SupabaseRESTClient.freshSession()
        struct Body: Encodable { let avatar_config: AvatarConfig? }
        let body = try SupabaseRESTClient.encoder.encode(Body(avatar_config: nil))
        let request = try SupabaseRESTClient.request(
            "PATCH", path: "profiles",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(session.user.id)")],
            body: body, accessToken: session.accessToken,
            extraHeaders: ["Prefer": "return=minimal"]
        )
        try await SupabaseRESTClient.send(request)
    }
}
