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
    private func rpcRequest(path: String, body: [String: String], accessToken: String) throws -> URLRequest {
        try SupabaseRESTClient.request(
            "POST", path: "rpc/\(path)", body: try SupabaseRESTClient.encoder.encode(body), accessToken: accessToken
        )
    }

    func checkIn(venueId: String, tripId: String?) async throws -> String {
        let session = try await SupabaseRESTClient.freshSession()
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
        let session = try await SupabaseRESTClient.freshSession()
        let request = try rpcRequest(path: "check_out_venue", body: ["p_checkin_id": checkinId], accessToken: session.accessToken)
        guard (try? await SupabaseRESTClient.send(request)) != nil else { throw VenueCheckinError.network }
    }

    func getActiveCheckin() async throws -> ActiveCheckin? {
        let session = try await SupabaseRESTClient.freshSession()
        let request = try rpcRequest(path: "get_active_checkin", body: [:], accessToken: session.accessToken)
        guard let data = try? await SupabaseRESTClient.send(request) else { throw VenueCheckinError.network }
        let rows = try SupabaseRESTClient.decoder.decode([ActiveCheckin].self, from: data)
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
