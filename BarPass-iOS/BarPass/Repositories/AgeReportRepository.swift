import Foundation

protocol AgeReportRepository: Sendable {
    /// One report per user per venue per day (unique constraint) — a
    /// duplicate submission is silently a no-op, not an error the UI needs
    /// to handle.
    func reportPerceivedAge(venueId: String, bracket: String) async throws
}

final actor SupabaseAgeReportRepository: AgeReportRepository {
    func reportPerceivedAge(venueId: String, bracket: String) async throws {
        let session = try await SupabaseRESTClient.freshSession()
        // user_id sent explicitly. Found 2026-09-08 while testing price
        // reports: the RLS policy is `user_id = auth.uid()` and the column has
        // no default, so every age report the app ever sent was a 403 that
        // the caller's `try?` swallowed — zero rows landed, silently.
        struct Body: Encodable { let venue_id: String; let user_id: String; let bracket: String }
        let body = try SupabaseRESTClient.encoder.encode(Body(venue_id: venueId, user_id: session.user.id, bracket: bracket))
        let request = try SupabaseRESTClient.request(
            "POST", path: "venue_age_reports", body: body, accessToken: session.accessToken,
            extraHeaders: ["Prefer": "return=minimal,resolution=ignore-duplicates"]
        )
        try await SupabaseRESTClient.send(request)
    }
}
