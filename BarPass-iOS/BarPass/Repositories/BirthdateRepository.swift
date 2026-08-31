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
    func setBirthdate(_ date: Date) async throws {
        let session = try await SupabaseRESTClient.freshSession()

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        struct Body: Encodable { let birthdate: String }
        let body = try SupabaseRESTClient.encoder.encode(Body(birthdate: formatter.string(from: date)))

        let request = try SupabaseRESTClient.request(
            "PATCH", path: "profiles",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(session.user.id)")],
            body: body, accessToken: session.accessToken,
            extraHeaders: ["Prefer": "return=minimal"]
        )

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
