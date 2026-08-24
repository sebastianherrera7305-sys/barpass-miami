import Foundation

protocol StadiumRepository: Sendable {
    func allStadiums() async throws -> [Stadium]
    func pois(stadiumId: String) async throws -> [StadiumPOI]
    func events(stadiumId: String) async throws -> [StadiumEvent]
}

final actor SupabaseStadiumRepository: StadiumRepository {
    private static let supabaseURL = SupabaseConfig.url.absoluteString
    private static let anonKey = SupabaseConfig.anonKey
    private static let stadiumColumns = "id,name,address,lat,lng,source_url"
    private static let poiColumns = "id,stadium_id,level_name,level_order,name,poi_type,section_or_concourse,source_url,confidence"
    private static let eventColumns = "id,stadium_id,name,starts_at,ticket_url,image_url"

    private func get<T: Decodable>(_ path: String, queryItems: [URLQueryItem]) async throws -> T {
        var components = URLComponents(string: "\(Self.supabaseURL)/rest/v1/\(path)")
        components?.queryItems = queryItems
        guard let url = components?.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue(Self.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(Self.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }

    func allStadiums() async throws -> [Stadium] {
        let rows: [StadiumRow] = try await get("stadiums", queryItems: [
            URLQueryItem(name: "select", value: Self.stadiumColumns),
            URLQueryItem(name: "order", value: "name.asc"),
        ])
        return rows.map { Stadium(id: $0.id, name: $0.name, address: $0.address, lat: $0.lat, lng: $0.lng, sourceURL: $0.sourceUrl) }
    }

    func pois(stadiumId: String) async throws -> [StadiumPOI] {
        let rows: [POIRow] = try await get("stadium_pois", queryItems: [
            URLQueryItem(name: "select", value: Self.poiColumns),
            URLQueryItem(name: "stadium_id", value: "eq.\(stadiumId)"),
            URLQueryItem(name: "order", value: "level_order.asc,name.asc"),
        ])
        return rows.map {
            StadiumPOI(
                id: $0.id, stadiumId: $0.stadiumId, levelName: $0.levelName, levelOrder: $0.levelOrder,
                name: $0.name, type: StadiumPOIType(rawValue: $0.poiType) ?? .other,
                sectionOrConcourse: $0.sectionOrConcourse, sourceURL: $0.sourceUrl, confidence: $0.confidence
            )
        }
    }

    func events(stadiumId: String) async throws -> [StadiumEvent] {
        let rows: [EventRow] = try await get("stadium_events", queryItems: [
            URLQueryItem(name: "select", value: Self.eventColumns),
            URLQueryItem(name: "stadium_id", value: "eq.\(stadiumId)"),
            URLQueryItem(name: "order", value: "starts_at.asc"),
        ])
        return rows.map {
            StadiumEvent(id: $0.id, stadiumId: $0.stadiumId, name: $0.name, startsAt: $0.startsAt, ticketURL: $0.ticketUrl, imageURL: $0.imageUrl)
        }
    }
}

private struct StadiumRow: Decodable {
    let id: String, name: String, address: String, lat: Double?, lng: Double?, sourceUrl: String
}

private struct POIRow: Decodable {
    let id: String, stadiumId: String, levelName: String, levelOrder: Int, name: String
    let poiType: String, sectionOrConcourse: String?, sourceUrl: String, confidence: String
}

private struct EventRow: Decodable {
    let id: String, stadiumId: String, name: String, startsAt: Date, ticketUrl: String?, imageUrl: String?
}
