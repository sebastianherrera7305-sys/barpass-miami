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
        struct Body: Encodable { let venue_id: String; let bracket: String }
        let body = try SupabaseRESTClient.encoder.encode(Body(venue_id: venueId, bracket: bracket))
        let request = try SupabaseRESTClient.request(
            "POST", path: "venue_age_reports", body: body, accessToken: session.accessToken,
            extraHeaders: ["Prefer": "return=minimal,resolution=ignore-duplicates"]
        )
        try await SupabaseRESTClient.send(request)
    }
}
