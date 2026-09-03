import Foundation

protocol DisplayNameRepository: Sendable {
    func getDisplayName() async throws -> String?
    func setDisplayName(_ name: String) async throws
}

/// `profiles.display_name` is already writable by its owner under the
/// existing "update own profile" RLS policy (schema.sql) — same as
/// home_address, no new column protection needed here the way bpx_points/
/// student_verified required (a user changing their own display name isn't
/// a privilege escalation). This was never actually wired up client-side:
/// ProfileView showed the l10n placeholder string "Tu Nombre"/"Your Name"
/// unconditionally instead of the real value, so every single profile
/// looked identical and unnamed — which also meant a chapter member roster
/// had nothing real to show per member.
final actor SupabaseDisplayNameRepository: DisplayNameRepository {
    func getDisplayName() async throws -> String? {
        let session = try await SupabaseRESTClient.freshSession()
        let request = try SupabaseRESTClient.request(
            "GET", path: "profiles",
            queryItems: [
                URLQueryItem(name: "id", value: "eq.\(session.user.id)"),
                URLQueryItem(name: "select", value: "display_name"),
            ],
            accessToken: session.accessToken
        )
        let data = try await SupabaseRESTClient.send(request)
        struct Row: Decodable { let displayName: String? }
        return try SupabaseRESTClient.decoder.decode([Row].self, from: data).first?.displayName
    }

    func setDisplayName(_ name: String) async throws {
        let session = try await SupabaseRESTClient.freshSession()
        struct Body: Encodable { let display_name: String }
        let body = try SupabaseRESTClient.encoder.encode(Body(display_name: name))
        let request = try SupabaseRESTClient.request(
            "PATCH", path: "profiles",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(session.user.id)")],
            body: body, accessToken: session.accessToken,
            extraHeaders: ["Prefer": "return=minimal"]
        )
        try await SupabaseRESTClient.send(request)
    }
}
