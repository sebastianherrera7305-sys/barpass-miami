import Foundation

enum BirthdateError: Error {
    /// The DB trigger (`enforce_adult_birthdate`, the_grid.sql) rejected the
    /// write — this is the REAL age gate, not the client-side check below,
    /// which only exists so the button doesn't need a round-trip to tell the
    /// user something they typed is obviously wrong.
    case underage
    case network
}

protocol BirthdateRepository: Sendable {
    /// Throws `.underage` if the server-side trigger rejects it — never
    /// trust a client-side age check alone for something this sensitive.
    func setBirthdate(_ date: Date) async throws
}

final actor SupabaseBirthdateRepository: BirthdateRepository {
    private static let supabaseURL = SupabaseConfig.url.absoluteString
    private static let anonKey = SupabaseConfig.anonKey

    private func freshSession() async throws -> AuthSession {
        guard await AuthService.shared.refreshIfNeeded(),
              let session = AuthService.shared.restoreSession() else {
            throw URLError(.userAuthenticationRequired)
        }
        return session
    }

    func setBirthdate(_ date: Date) async throws {
        let session = try await freshSession()
        guard var components = URLComponents(string: "\(Self.supabaseURL)/rest/v1/profiles") else { throw URLError(.badURL) }
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(session.user.id)")]
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue(Self.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        struct Body: Encodable { let birthdate: String }
        request.httpBody = try JSONEncoder().encode(Body(birthdate: formatter.string(from: date)))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BirthdateError.network }
        if 200..<300 ~= http.statusCode { return }

        // Postgres error body for a trigger's RAISE EXCEPTION: {"code":
        // "P0001", "message": "must be at least 18 years old", ...}
        if let body = try? JSONDecoder().decode(PostgrestError.self, from: data),
           body.message.contains("18 years old") {
            throw BirthdateError.underage
        }
        throw BirthdateError.network
    }
}

private struct PostgrestError: Decodable {
    let message: String
}
