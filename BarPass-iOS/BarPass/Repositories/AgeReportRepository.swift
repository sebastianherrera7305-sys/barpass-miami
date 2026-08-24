import Foundation

protocol AgeReportRepository: Sendable {
    /// One report per user per venue per day (unique constraint) — a
    /// duplicate submission is silently a no-op, not an error the UI needs
    /// to handle.
    func reportPerceivedAge(venueId: String, bracket: String) async throws
}

final actor SupabaseAgeReportRepository: AgeReportRepository {
    private static let supabaseURL = SupabaseConfig.url.absoluteString
    private static let anonKey = SupabaseConfig.anonKey

    func reportPerceivedAge(venueId: String, bracket: String) async throws {
        guard await AuthService.shared.refreshIfNeeded(),
              let session = AuthService.shared.restoreSession() else {
            throw URLError(.userAuthenticationRequired)
        }
        guard let url = URL(string: "\(Self.supabaseURL)/rest/v1/venue_age_reports") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(Self.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal,resolution=ignore-duplicates", forHTTPHeaderField: "Prefer")

        struct Body: Encodable { let venue_id: String; let bracket: String }
        request.httpBody = try JSONEncoder().encode(Body(venue_id: venueId, bracket: bracket))

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
    }
}
