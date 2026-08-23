import Foundation

final actor SupabaseGreekLifeRepository: GreekLifeRepository {
    private static let supabaseURL = SupabaseConfig.url.absoluteString
    private static let anonKey = SupabaseConfig.anonKey

    private static let universityColumns = "id,name,short_name,city,metro_city,state,country,official_url,greek_life_url,lat,lng,party_life_notes"
    private static let chapterColumns = "id,university_id,fraternity_name,chapter_designation,council,status,official_source_url,chapter_url,address,lat,lng,address_verified,needs_review,review_reason"

    private var universitiesByCity: [String: [University]] = [:]
    private var chaptersByUniversity: [String: [GreekChapter]] = [:]
    private var allUniversitiesCache: [University]?

    func universities(forCity city: String) async throws -> [University] {
        if let cached = universitiesByCity[city] { return cached }
        guard var components = URLComponents(string: "\(Self.supabaseURL)/rest/v1/universities") else { throw URLError(.badURL) }
        // Matches either the university's real city or its metro_city (e.g.
        // Coral Gables schools surface under "Miami") — never a fuzzy/ilike
        // match, both sides are exact real values.
        components.queryItems = [
            URLQueryItem(name: "select", value: Self.universityColumns),
            URLQueryItem(name: "or", value: "(city.eq.\(city),metro_city.eq.\(city))"),
        ]
        guard let url = components.url else { throw URLError(.badURL) }

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
        let rows = try decoder.decode([SupabaseUniversityRow].self, from: data)
        let result = rows.map(Self.mapUniversity)
        universitiesByCity[city] = result
        return result
    }

    func chapters(forUniversity universityId: String) async throws -> [GreekChapter] {
        if let cached = chaptersByUniversity[universityId] { return cached }
        guard var components = URLComponents(string: "\(Self.supabaseURL)/rest/v1/greek_chapters") else { throw URLError(.badURL) }
        components.queryItems = [
            URLQueryItem(name: "select", value: Self.chapterColumns),
            URLQueryItem(name: "university_id", value: "eq.\(universityId)"),
            URLQueryItem(name: "order", value: "council.asc,fraternity_name.asc"),
        ]
        guard let url = components.url else { throw URLError(.badURL) }

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
        let rows = try decoder.decode([SupabaseChapterRow].self, from: data)
        let result = rows.map(Self.mapChapter)
        chaptersByUniversity[universityId] = result
        return result
    }

    func allUniversities() async throws -> [University] {
        if let cached = allUniversitiesCache { return cached }
        guard var components = URLComponents(string: "\(Self.supabaseURL)/rest/v1/universities") else { throw URLError(.badURL) }
        components.queryItems = [
            URLQueryItem(name: "select", value: Self.universityColumns),
            URLQueryItem(name: "order", value: "name.asc"),
        ]
        guard let url = components.url else { throw URLError(.badURL) }

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
        let rows = try decoder.decode([SupabaseUniversityRow].self, from: data)
        let result = rows.map(Self.mapUniversity)
        allUniversitiesCache = result
        return result
    }

    func university(id: String) async throws -> University? {
        try await allUniversities().first { $0.id == id }
    }

    func chapter(id: String) async throws -> GreekChapter? {
        for (_, chapters) in chaptersByUniversity {
            if let match = chapters.first(where: { $0.id == id }) { return match }
        }
        guard var components = URLComponents(string: "\(Self.supabaseURL)/rest/v1/greek_chapters") else { throw URLError(.badURL) }
        components.queryItems = [
            URLQueryItem(name: "select", value: Self.chapterColumns),
            URLQueryItem(name: "id", value: "eq.\(id)"),
        ]
        guard let url = components.url else { throw URLError(.badURL) }

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
        let rows = try decoder.decode([SupabaseChapterRow].self, from: data)
        return rows.first.map(Self.mapChapter)
    }

    private static func mapUniversity(_ row: SupabaseUniversityRow) -> University {
        University(
            id: row.id,
            name: row.name,
            shortName: row.shortName,
            city: row.city,
            metroCity: row.metroCity,
            state: row.state,
            country: row.country,
            officialURL: row.officialUrl,
            greekLifeURL: row.greekLifeUrl,
            lat: row.lat,
            lng: row.lng,
            partyLifeNotes: row.partyLifeNotes
        )
    }

    private static func mapChapter(_ row: SupabaseChapterRow) -> GreekChapter {
        GreekChapter(
            id: row.id,
            universityId: row.universityId,
            fraternityName: row.fraternityName,
            chapterDesignation: row.chapterDesignation,
            council: GreekCouncil(rawValue: row.council) ?? .other,
            status: ChapterStatus(rawValue: row.status) ?? .unknown,
            officialSourceURL: row.officialSourceUrl,
            chapterURL: row.chapterUrl,
            address: row.address,
            lat: row.lat,
            lng: row.lng,
            addressVerified: row.addressVerified,
            needsReview: row.needsReview,
            reviewReason: row.reviewReason
        )
    }
}

private struct SupabaseUniversityRow: Decodable {
    let id: String
    let name: String
    let shortName: String?
    let city: String
    let metroCity: String?
    let state: String?
    let country: String
    let officialUrl: String?
    let greekLifeUrl: String?
    let lat: Double?
    let lng: Double?
    let partyLifeNotes: String?
}

private struct SupabaseChapterRow: Decodable {
    let id: String
    let universityId: String
    let fraternityName: String
    let chapterDesignation: String?
    let council: String
    let status: String
    let officialSourceUrl: String
    let chapterUrl: String?
    let address: String?
    let lat: Double?
    let lng: Double?
    let addressVerified: Bool
    let needsReview: Bool
    let reviewReason: String?
}
