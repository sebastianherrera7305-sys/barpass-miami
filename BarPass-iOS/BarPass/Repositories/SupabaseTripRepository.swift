import Foundation

/// Real Supabase-backed trips (`public.trips`, see
/// barpass-v2/supabase/trips_schema.sql — must be run once in the Supabase
/// SQL editor before this works). `Trip` itself is the wire format: with
/// `.convertToSnakeCase`/`.convertFromSnakeCase` its field names line up
/// exactly with the table's snake_case columns (creatorId ⇄ creator_id,
/// etc.), including the nested `stops` jsonb column since `Stop`'s own
/// field names have no underscores and pass through the conversion
/// unchanged either way.
///
/// Requires a real signed-in session — RLS scopes every row to
/// `auth.uid()`, so guest mode (no session) can't read/write trips at all.
actor SupabaseTripRepository: TripRepository {
    private static let supabaseURL = SupabaseConfig.url.absoluteString
    private static let anonKey = SupabaseConfig.anonKey

    private static let columns = "id,creator_id,title,destination_city,start_date,end_date,cover_image,visibility,status,member_ids,co_organizer_ids,pending_requests,invite_code,stops"

    struct NoSessionError: LocalizedError {
        // Was hardcoded Spanish, so a device set to English showed this
        // raw string as the error subtitle underneath the (correctly
        // localized) "Something went wrong" title — routed through L10n
        // like every other user-facing string now.
        var errorDescription: String? { L10n.shared.t("trips.error.noSession") }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func session() throws -> AuthSession {
        guard let s = AuthService.shared.restoreSession() else { throw NoSessionError() }
        return s
    }

    private func request(_ method: String, path: String, body: Data? = nil) throws -> URLRequest {
        guard let url = URL(string: "\(Self.supabaseURL)/rest/v1/\(path)") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(Self.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(try session().accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body { req.httpBody = body }
        return req
    }

    // MARK: - TripRepository

    func getTrips() async throws -> [Trip] {
        let req = try request("GET", path: "trips?select=\(Self.columns)&order=start_date.asc")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        return try Self.decoder.decode([Trip].self, from: data)
    }

    func saveTrip(_ trip: Trip) async throws {
        let body = try Self.encoder.encode(trip)
        var req = try request("POST", path: "trips", body: body)
        req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? "save failed"])
        }
    }

    func updateTrip(_ trip: Trip) async throws {
        let body = try Self.encoder.encode(trip)
        var req = try request("PATCH", path: "trips?id=eq.\(trip.id)", body: body)
        req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? "update failed"])
        }
    }

    func deleteTrip(_ trip: Trip) async throws {
        let req = try request("DELETE", path: "trips?id=eq.\(trip.id)")
        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
    }

    struct InviteNotFoundError: LocalizedError {
        var errorDescription: String? { L10n.shared.t("trips.error.inviteNotFound") }
    }

    /// Calls the `redeem_trip_invite` RPC (SECURITY DEFINER) instead of a
    /// plain SELECT filter — a naive client-side lookup by invite_code would
    /// either be blocked by RLS for private trips, or leak every private
    /// trip's full row to anyone probing without a filter. The RPC does the
    /// lookup + join atomically server-side and returns only the one row.
    func joinByInviteCode(_ code: String) async throws -> Trip {
        let body = try JSONSerialization.data(withJSONObject: ["p_code": code])
        let req = try request("POST", path: "rpc/redeem_trip_invite", body: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard 200..<300 ~= http.statusCode else {
            if let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
               let msg = obj["message"] as? String, msg.contains("invite_not_found") {
                throw InviteNotFoundError()
            }
            throw URLError(.badServerResponse)
        }
        return try Self.decoder.decode(Trip.self, from: data)
    }
}
