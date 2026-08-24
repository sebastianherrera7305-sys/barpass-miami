import Foundation

struct ActiveCheckin: Codable, Sendable {
    let checkinId: String
    let venueId: String
    let checkedInAt: Date
}

enum VenueCheckinError: Error {
    /// profiles.birthdate is null — happens if AgeGateView's best-effort
    /// server write (see setBirthdate) never landed (offline at signup,
    /// etc.). The check-in RPC needs a real birthdate, no exceptions.
    case birthdateRequired
    case underage
    case network
}

protocol VenueCheckinRepository: Sendable {
    /// Auto-closes any other still-open checkin first — a user is "at" one
    /// venue at a time. Idempotent: re-checking into the same venue returns
    /// the existing row instead of duplicating it.
    func checkIn(venueId: String, tripId: String?) async throws -> String
    /// Takes the checkin's own id (from `checkIn`'s return value or
    /// `getActiveCheckin()`), not the venue id — matches `check_out_venue`'s
    /// real signature.
    func checkOut(checkinId: String) async throws
    func getActiveCheckin() async throws -> ActiveCheckin?
}

final actor SupabaseVenueCheckinRepository: VenueCheckinRepository {
    private static let supabaseURL = SupabaseConfig.url.absoluteString
    private static let anonKey = SupabaseConfig.anonKey

    private func freshSession() async throws -> AuthSession {
        guard await AuthService.shared.refreshIfNeeded(),
              let session = AuthService.shared.restoreSession() else {
            throw URLError(.userAuthenticationRequired)
        }
        return session
    }

    private func rpcRequest(path: String, body: [String: String], accessToken: String) throws -> URLRequest {
        guard let url = URL(string: "\(Self.supabaseURL)/rest/v1/rpc/\(path)") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(Self.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    func checkIn(venueId: String, tripId: String?) async throws -> String {
        let session = try await freshSession()
        var body = ["p_venue_id": venueId]
        if let tripId { body["p_trip_id"] = tripId }
        let request = try rpcRequest(path: "check_in_venue", body: body, accessToken: session.accessToken)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw VenueCheckinError.network }
        guard 200..<300 ~= http.statusCode else { throw Self.mapError(data) }

        // The RPC returns a bare JSON string (the uuid), not an object.
        guard let id = try? JSONDecoder().decode(String.self, from: data) else { throw VenueCheckinError.network }
        return id
    }

    func checkOut(checkinId: String) async throws {
        let session = try await freshSession()
        let request = try rpcRequest(path: "check_out_venue", body: ["p_checkin_id": checkinId], accessToken: session.accessToken)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw VenueCheckinError.network
        }
    }

    func getActiveCheckin() async throws -> ActiveCheckin? {
        let session = try await freshSession()
        let request = try rpcRequest(path: "get_active_checkin", body: [:], accessToken: session.accessToken)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw VenueCheckinError.network
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let rows = try decoder.decode([ActiveCheckin].self, from: data)
        return rows.first
    }

    private static func mapError(_ data: Data) -> VenueCheckinError {
        guard let json = try? JSONDecoder().decode([String: String].self, from: data),
              let message = json["message"] else { return .network }
        if message.contains("birthdate required") { return .birthdateRequired }
        if message.contains("18+") { return .underage }
        return .network
    }
}
