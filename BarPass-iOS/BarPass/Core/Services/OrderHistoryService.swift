import Foundation

/// Reads the signed-in user's own orders and passes straight from Supabase
/// REST — RLS ("readable by owner") does the scoping, so no server route
/// is needed just to display history.
enum OrderHistoryService {
    private static let supabaseURL = SupabaseConfig.url.absoluteString
    private static let anonKey = SupabaseConfig.anonKey

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

    static func fetchOrders(session: AuthSession) async -> [OrderRow] {
        await fetch(path: "orders?select=id,vendor_id,total,payment_method,status,created_at&order=created_at.desc&limit=50", session: session)
    }

    static func fetchPasses(session: AuthSession) async -> [PassRow] {
        await fetch(path: "passes?select=id,pass_code,kind,venue_name,quantity,amount,valid_until,redeemed_at,created_at&order=created_at.desc&limit=50", session: session)
    }

    private static func fetch<T: Decodable>(path: String, session: AuthSession) async -> [T] {
        guard let url = URL(string: "\(supabaseURL)/rest/v1/\(path)") else { return [] }
        var request = URLRequest(url: url)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds
        return (try? decoder.decode([T].self, from: data)) ?? []
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
