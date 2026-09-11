import Foundation

/// Reads the signed-in user's own orders and passes straight from Supabase
/// REST — RLS ("readable by owner") does the scoping, so no server route
/// is needed just to display history.
enum OrderHistoryService {
    struct OrderRow: Decodable {
        let id: String
        let vendor_id: String
        let total: Double
        let payment_method: String
        let status: String
        let created_at: Date
    }

    struct PassRow: Decodable {
        let id: String
        let pass_code: String
        let kind: String
        let venue_name: String
        let quantity: Int
        let amount: Double
        let valid_until: Date
        let redeemed_at: Date?
        let created_at: Date
    }

    static func fetchOrders() async throws -> [OrderRow] {
        try await fetch(path: "orders?select=id,vendor_id,total,payment_method,status,created_at&order=created_at.desc&limit=50")
    }

    static func fetchPasses() async throws -> [PassRow] {
        try await fetch(path: "passes?select=id,pass_code,kind,venue_name,quantity,amount,valid_until,redeemed_at,created_at&order=created_at.desc&limit=50")
    }

    /// Throws instead of swallowing. `try?` on the request plus `?? []` on the
    /// decode used to turn every failure — most importantly an expired JWT
    /// coming back 401 — into a cheerful "no orders yet", so a user who had
    /// just paid opened their history and saw an empty state. A stale token is
    /// also why this now goes through `SupabaseRESTClient.freshSession()` like
    /// the rest of the RLS-scoped reads, instead of taking whatever token the
    /// caller happened to be holding.
    private static func fetch<T: Decodable>(path: String) async throws -> [T] {
        let session = try await SupabaseRESTClient.freshSession()
        let request = try SupabaseRESTClient.request("GET", path: path, accessToken: session.accessToken)
        let data = try await SupabaseRESTClient.send(request)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds
        return try decoder.decode([T].self, from: data)
    }
}

private extension JSONDecoder.DateDecodingStrategy {
    static var iso8601WithFractionalSeconds: JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: string) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(string)")
        }
    }
}
