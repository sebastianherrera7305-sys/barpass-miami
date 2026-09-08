import Foundation

/// "¿Cuánto pagaste por un trago?" — asked at check-out, the moment the
/// person actually knows. Feeds venue_price_reports; venue_price_stats
/// (supabase/venue_price_reports.sql) turns 3+ reports into the median the
/// app shows. Venue websites publish drink prices for only ~1 in 5 venues,
/// so this is how the number reaches the other four.
protocol PriceReportRepository: Sendable {
    /// One report per user per venue per day (unique constraint) — a
    /// duplicate is silently a no-op.
    func reportDrinkPrice(venueId: String, cents: Int) async throws
}

final actor SupabasePriceReportRepository: PriceReportRepository {
    func reportDrinkPrice(venueId: String, cents: Int) async throws {
        let session = try await SupabaseRESTClient.freshSession()
        // user_id sent explicitly: the RLS policy is `user_id = auth.uid()`
        // and the column has no default, so omitting it is a silent 403
        // (verified 2026-09-08 with a disposable user).
        struct Body: Encodable { let venue_id: String; let user_id: String; let drink_price_cents: Int }
        let body = try SupabaseRESTClient.encoder.encode(Body(venue_id: venueId, user_id: session.user.id, drink_price_cents: cents))
        let request = try SupabaseRESTClient.request(
            "POST", path: "venue_price_reports", body: body, accessToken: session.accessToken,
            extraHeaders: ["Prefer": "return=minimal,resolution=ignore-duplicates"]
        )
        try await SupabaseRESTClient.send(request)
    }
}
