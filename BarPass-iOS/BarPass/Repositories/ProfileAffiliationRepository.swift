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
    private static let supabaseURL = SupabaseConfig.url.absoluteString
    private static let anonKey = SupabaseConfig.anonKey

    /// Refreshes the session first (ADR-012) — the JWT lives ~59 minutes and
    /// nothing outside the login screen refreshes it otherwise, so a
    /// long-lived session would otherwise hit an expired token here — then
    /// returns the guaranteed-fresh session.
    private func freshSession() async throws -> AuthSession {
        guard await AuthService.shared.refreshIfNeeded(),
              let session = AuthService.shared.restoreSession() else {
            throw URLError(.userAuthenticationRequired)
        }
        return session
    }

    private func request(url: URL, accessToken: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(Self.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    func getAffiliation() async throws -> ProfileAffiliation {
        let session = try await freshSession()
        guard var components = URLComponents(string: "\(Self.supabaseURL)/rest/v1/profiles") else { throw URLError(.badURL) }
        components.queryItems = [
            URLQueryItem(name: "select", value: "university_id,chapter_id"),
            URLQueryItem(name: "id", value: "eq.\(session.user.id)"),
        ]
        guard let url = components.url else { throw URLError(.badURL) }
        let request = request(url: url, accessToken: session.accessToken)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let rows = try decoder.decode([ProfileAffiliation].self, from: data)
        return rows.first ?? ProfileAffiliation(universityId: nil, chapterId: nil)
    }

    func setAffiliation(universityId: String?, chapterId: String?) async throws {
        let session = try await freshSession()
        guard var components = URLComponents(string: "\(Self.supabaseURL)/rest/v1/profiles") else { throw URLError(.badURL) }
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(session.user.id)")]
        guard let url = components.url else { throw URLError(.badURL) }

        var request = request(url: url, accessToken: session.accessToken)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")

        struct Body: Encodable {
            let university_id: String?
            let chapter_id: String?
        }
        request.httpBody = try JSONEncoder().encode(Body(university_id: universityId, chapter_id: chapterId))

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
    }
}
