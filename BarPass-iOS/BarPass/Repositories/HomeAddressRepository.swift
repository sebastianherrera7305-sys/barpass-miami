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
    func setHomeAddress(_ address: HomeAddress) async throws {
        let session = try await SupabaseRESTClient.freshSession()
        struct Body: Encodable { let home_address: String; let home_lat: Double; let home_lng: Double }
        let body = try SupabaseRESTClient.encoder.encode(Body(home_address: address.address, home_lat: address.lat, home_lng: address.lng))
        let request = try SupabaseRESTClient.request(
            "PATCH", path: "profiles",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(session.user.id)")],
            body: body, accessToken: session.accessToken,
            extraHeaders: ["Prefer": "return=minimal"]
        )
        try await SupabaseRESTClient.send(request)
    }

    func getHomeAddress() async throws -> HomeAddress? {
        let session = try await SupabaseRESTClient.freshSession()
        let request = try SupabaseRESTClient.request(
            "GET", path: "profiles",
            queryItems: [
                URLQueryItem(name: "id", value: "eq.\(session.user.id)"),
                URLQueryItem(name: "select", value: "home_address,home_lat,home_lng"),
            ],
            accessToken: session.accessToken
        )
        let data = try await SupabaseRESTClient.send(request)
        struct Row: Decodable { let homeAddress: String?; let homeLat: Double?; let homeLng: Double? }
        guard let row = try SupabaseRESTClient.decoder.decode([Row].self, from: data).first,
              let address = row.homeAddress, let lat = row.homeLat, let lng = row.homeLng else {
            return nil
        }
        return HomeAddress(address: address, lat: lat, lng: lng)
    }
}
