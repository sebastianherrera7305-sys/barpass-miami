import Foundation

struct HomeAddress: Codable, Sendable {
    let address: String
    let lat: Double
    let lng: Double
}

protocol HomeAddressRepository: Sendable {
    func setHomeAddress(_ address: HomeAddress) async throws
    func getHomeAddress() async throws -> HomeAddress?
}

final actor SupabaseHomeAddressRepository: HomeAddressRepository {
    private static let supabaseURL = SupabaseConfig.url.absoluteString
    private static let anonKey = SupabaseConfig.anonKey

    private func freshSession() async throws -> AuthSession {
        guard await AuthService.shared.refreshIfNeeded(),
              let session = AuthService.shared.restoreSession() else {
            throw URLError(.userAuthenticationRequired)
        }
        return session
    }

    func setHomeAddress(_ address: HomeAddress) async throws {
        let session = try await freshSession()
        guard var components = URLComponents(string: "\(Self.supabaseURL)/rest/v1/profiles") else { throw URLError(.badURL) }
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(session.user.id)")]
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue(Self.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")

        struct Body: Encodable { let home_address: String; let home_lat: Double; let home_lng: Double }
        request.httpBody = try JSONEncoder().encode(Body(home_address: address.address, home_lat: address.lat, home_lng: address.lng))

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
    }

    func getHomeAddress() async throws -> HomeAddress? {
        let session = try await freshSession()
        guard var components = URLComponents(string: "\(Self.supabaseURL)/rest/v1/profiles") else { throw URLError(.badURL) }
        components.queryItems = [
            URLQueryItem(name: "id", value: "eq.\(session.user.id)"),
            URLQueryItem(name: "select", value: "home_address,home_lat,home_lng"),
        ]
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.setValue(Self.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        struct Row: Decodable { let homeAddress: String?; let homeLat: Double?; let homeLng: Double? }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let row = try decoder.decode([Row].self, from: data).first,
              let address = row.homeAddress, let lat = row.homeLat, let lng = row.homeLng else {
            return nil
        }
        return HomeAddress(address: address, lat: lat, lng: lng)
    }
}
