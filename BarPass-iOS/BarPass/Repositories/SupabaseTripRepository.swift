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
    private static let columns = "id,creator_id,title,destination_city,start_date,end_date,cover_image,visibility,status,member_ids,co_organizer_ids,pending_requests,invite_code,stops"

    struct NoSessionError: LocalizedError {
        // Was hardcoded Spanish, so a device set to English showed this
        // raw string as the error subtitle underneath the (correctly
        // localized) "Something went wrong" title — routed through L10n
        // like every other user-facing string now.
        var errorDescription: String? { L10n.tSync("trips.error.noSession") }
    }

    /// Trip's field names line up exactly with the table's snake_case
    /// columns via convertTo/FromSnakeCase, so it uses SupabaseRESTClient's
    /// shared coders directly — no local override needed.

    private func session() throws -> AuthSession {
        guard let s = AuthService.shared.restoreSession() else { throw NoSessionError() }
        return s
    }

    private func request(_ method: String, path: String, body: Data? = nil) throws -> URLRequest {
        try SupabaseRESTClient.request(method, path: path, body: body, accessToken: try session().accessToken)
    }

    // MARK: - TripRepository

    func getTrips() async throws -> [Trip] {
        let req = try request("GET", path: "trips?select=\(Self.columns)&order=start_date.asc")
        let data = try await SupabaseRESTClient.send(req)
        return try SupabaseRESTClient.decoder.decode([Trip].self, from: data)
    }

    func saveTrip(_ trip: Trip) async throws {
        let body = try SupabaseRESTClient.encoder.encode(trip)
        let req = try SupabaseRESTClient.request(
            "POST", path: "trips", body: body, accessToken: try session().accessToken,
            extraHeaders: ["Prefer": "return=minimal"]
        )
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? "save failed"])
        }
    }

    func updateTrip(_ trip: Trip) async throws {
        let body = try SupabaseRESTClient.encoder.encode(trip)
        let req = try SupabaseRESTClient.request(
            "PATCH", path: "trips", queryItems: [URLQueryItem(name: "id", value: "eq.\(trip.id)")],
            body: body, accessToken: try session().accessToken,
            extraHeaders: ["Prefer": "return=minimal"]
        )
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? "update failed"])
        }
    }

    func deleteTrip(_ trip: Trip) async throws {
        let req = try request("DELETE", path: "trips?id=eq.\(trip.id)")
        try await SupabaseRESTClient.send(req)
    }

    struct InviteNotFoundError: LocalizedError {
        var errorDescription: String? { L10n.tSync("trips.error.inviteNotFound") }
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
        return try SupabaseRESTClient.decoder.decode(Trip.self, from: data)
    }
}
