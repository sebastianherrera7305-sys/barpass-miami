import Foundation

/// "Votan entre varios spots y gana uno."
///
/// A trip already carries its members and an ordered list of stops. The only
/// thing missing to settle "where are we actually going" was a vote per member
/// per stop — so the stops ARE the options. A separate poll object would
/// duplicate them and drift out of sync with the itinerary the moment someone
/// edits it.
///
/// Access is membership, enforced server-side (supabase/trip_stop_votes.sql):
/// you see and cast votes only on a trip you belong to, you can only ever
/// delete your own vote, and there is no UPDATE policy — a vote is cast or
/// withdrawn, never edited.
protocol TripStopVoteRepository: Sendable {
    /// stop id -> the user ids who voted for it. Empty for a trip nobody has
    /// voted on yet, which is the normal state, not an error.
    func votes(tripId: String) async throws -> [String: [String]]
    /// Casting again is a no-op, not a second vote: a unique index on
    /// (stop_id, user_id) makes double-voting impossible server-side.
    func vote(tripId: String, stopId: String) async throws
    func unvote(stopId: String) async throws
}

final actor SupabaseTripStopVoteRepository: TripStopVoteRepository {
    private struct Row: Decodable { let stopId: String; let userId: String }

    func votes(tripId: String) async throws -> [String: [String]] {
        let session = try await SupabaseRESTClient.freshSession()
        let request = try SupabaseRESTClient.request(
            "GET", path: "trip_stop_votes",
            queryItems: [
                URLQueryItem(name: "select", value: "stop_id,user_id"),
                URLQueryItem(name: "trip_id", value: "eq.\(tripId)"),
            ],
            accessToken: session.accessToken
        )
        let data = try await SupabaseRESTClient.send(request)
        let rows = try SupabaseRESTClient.decoder.decode([Row].self, from: data)
        return Dictionary(grouping: rows, by: \.stopId).mapValues { $0.map(\.userId) }
    }

    func vote(tripId: String, stopId: String) async throws {
        let session = try await SupabaseRESTClient.freshSession()
        // user_id sent explicitly. The insert policy checks
        // `auth.uid() = user_id` and the column has no default, so omitting it
        // is a silent 403 — the same trap that swallowed every age report.
        struct Body: Encodable { let trip_id: String; let stop_id: String; let user_id: String }
        let body = try SupabaseRESTClient.encoder.encode(
            Body(trip_id: tripId, stop_id: stopId, user_id: session.user.id))
        let request = try SupabaseRESTClient.request(
            "POST", path: "trip_stop_votes", body: body, accessToken: session.accessToken,
            extraHeaders: ["Prefer": "return=minimal,resolution=ignore-duplicates"]
        )
        try await SupabaseRESTClient.send(request)
    }

    func unvote(stopId: String) async throws {
        let session = try await SupabaseRESTClient.freshSession()
        // No user_id filter needed — the delete policy already restricts this
        // to the caller's own row, and sending one would only invite a bug.
        let request = try SupabaseRESTClient.request(
            "DELETE", path: "trip_stop_votes",
            queryItems: [URLQueryItem(name: "stop_id", value: "eq.\(stopId)")],
            accessToken: session.accessToken,
            extraHeaders: ["Prefer": "return=minimal"]
        )
        try await SupabaseRESTClient.send(request)
    }
}
