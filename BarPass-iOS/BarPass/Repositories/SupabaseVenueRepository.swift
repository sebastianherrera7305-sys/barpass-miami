import Foundation

final actor SupabaseVenueRepository: VenueRepository {
    private var loadedVenues: [BarPassVenue]?

    private static let supabaseURL = SupabaseConfig.url.absoluteString
    private static let anonKey = SupabaseConfig.anonKey

    /// Exact columns the decoder uses — `select=*` shipped dead columns on
    /// every app launch (egress is the free-tier bottleneck).
    private static let venueColumns = "id,slug,name,type,neighborhood,address,lat,lng,hook,description,rating,review_count,cover_men,cover_women,avg_spend,open_time,close_time,happy_hour_until,music_genres,vibes,dress_code,parking,crowd_level,best_arrival_time,peak_hours,popular_drinks,emoji,image_url,instagram_handle,is_trending,phone,website,wheelchair_accessible,outdoor_seating,good_for_groups,good_for_watching_sports,has_live_music,reservable,serves_vegetarian_food,restroom,city,country,timezone"
    private static let eventColumns = "id,venue_id,title,description,starts_at,ends_at,cover_price"
    private static let tagColumns = "venue_id,tag_id,category,confidence,source,computed_at"

    /// Cache en disco de la última lista real obtenida — antes el fallback
    /// sin red era 1 sola venue hardcodeada de preview (LocalVenueRepository),
    /// lo cual hacía que la app se sintiera rota sin conexión.
    private static let cacheURL: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("BarPassVenueCache.json")
    }()

    private func ensureVenues() async throws -> [BarPassVenue] {
        if let venues = loadedVenues { return venues }
        let venues = await fetchVenuesWithFallback()
        loadedVenues = venues
        return venues
    }

    private func fetchVenuesWithFallback() async -> [BarPassVenue] {
        do {
            let venues = try await fetchFromSupabase()
            persistCache(venues)
            return venues
        } catch {
            #if DEBUG
            print("⚠️ SupabaseVenueRepository: fetch failed, falling back to cache. Error: \(error)")
            #endif
            if let cached = readCache(), !cached.isEmpty {
                return cached
            }
            do {
                return try await LocalVenueRepository().getVenues()
            } catch {
                #if DEBUG
                print("⚠️ SupabaseVenueRepository: fallback also failed. Returning empty array.")
                #endif
                return []
            }
        }
    }

    private func persistCache(_ venues: [BarPassVenue]) {
        guard let data = try? JSONEncoder().encode(venues) else { return }
        try? data.write(to: Self.cacheURL, options: .atomic)
    }

    private func readCache() -> [BarPassVenue]? {
        guard let data = try? Data(contentsOf: Self.cacheURL) else { return nil }
        return try? JSONDecoder().decode([BarPassVenue].self, from: data)
    }

    private func fetchFromSupabase() async throws -> [BarPassVenue] {
        async let venueRowsTask = fetchVenueRows()
        async let eventRowsTask = fetchEventRows()
        async let tagRowsTask = fetchExperienceTagRows()
        let venueRows = try await venueRowsTask
        let eventRows = (try? await eventRowsTask) ?? []
        let tagRows = (try? await tagRowsTask) ?? []
        let eventsByVenue = Dictionary(grouping: eventRows, by: { $0.venueId.uuidString.lowercased() })
        let tagsByVenue = Dictionary(grouping: tagRows, by: { $0.venueId.uuidString.lowercased() })

        return venueRows.map { row in
            let venueEvents: [VenueEvent] = (eventsByVenue[row.id.uuidString.lowercased()] ?? []).map { event in
                VenueEvent(
                    id: event.id.uuidString,
                    title: event.title,
                    date: event.startsAt,
                    coverPrice: event.coverPrice.map(Double.init),
                    description: event.description,
                    endDate: event.endsAt
                )
            }
            let venueTags: [ExperienceTag] = (tagsByVenue[row.id.uuidString.lowercased()] ?? []).map { tag in
                ExperienceTag(id: tag.tagId, category: tag.category, confidence: tag.confidence, source: tag.source, updatedAt: tag.computedAt)
            }
            return Self.mapRowToVenue(row, events: venueEvents, experienceTags: venueTags)
        }
    }

    private func fetchVenueRows() async throws -> [SupabaseVenueRow] {
        guard let url = URL(string: "\(Self.supabaseURL)/rest/v1/venues?select=\(Self.venueColumns)") else { throw URLError(.badURL) }
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
        return try decoder.decode([SupabaseVenueRow].self, from: data)
    }

    private func fetchEventRows() async throws -> [SupabaseEventRow] {
        guard let url = URL(string: "\(Self.supabaseURL)/rest/v1/events?select=\(Self.eventColumns)") else { throw URLError(.badURL) }
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
        return try decoder.decode([SupabaseEventRow].self, from: data)
    }

    private func fetchExperienceTagRows() async throws -> [SupabaseExperienceTagRow] {
        guard let url = URL(string: "\(Self.supabaseURL)/rest/v1/venue_experience_tags?select=\(Self.tagColumns)") else { throw URLError(.badURL) }
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
        return try decoder.decode([SupabaseExperienceTagRow].self, from: data)
    }

    // MARK: - VenueRepository

    func getVenues() async throws -> [BarPassVenue] {
        try await ensureVenues()
    }

    func getVenue(id: String) async throws -> BarPassVenue? {
        try await ensureVenues().first { $0.id == id }
    }

    func getTrendingVenues() async throws -> [BarPassVenue] {
        try await ensureVenues().filter { $0.isTrending }
    }

    func getOpenNowVenues() async throws -> [BarPassVenue] {
        try await ensureVenues().filter { $0.isOpenNow }
    }

    func getHappyHourVenues() async throws -> [BarPassVenue] {
        try await ensureVenues().filter { $0.hasHappyHour }
    }

    func getVenuesByNeighborhood(_ neighborhood: String) async throws -> [BarPassVenue] {
        try await ensureVenues().filter { $0.neighborhood == neighborhood }
    }

    func searchVenues(query: String) async throws -> [BarPassVenue] {
        let venues = try await ensureVenues()
        guard !query.isEmpty else { return venues }
        let q = query.lowercased()
        return venues.filter {
            $0.name.lowercased().contains(q) ||
            $0.neighborhood.lowercased().contains(q) ||
            $0.tags.contains { $0.lowercased().contains(q) }
        }
    }

    // MARK: - Mapping

    private static func mapRowToVenue(_ row: SupabaseVenueRow, events: [VenueEvent], experienceTags: [ExperienceTag] = []) -> BarPassVenue {
        BarPassVenue(
            id: row.id.uuidString.lowercased(),
            name: row.name,
            neighborhood: row.neighborhood,
            address: row.address,
            latitude: row.lat,
            longitude: row.lng,
            type: mapType(row.type),
            vibes: row.vibes ?? [],
            musicGenres: (row.musicGenres ?? []).compactMap { Self.mapGenre($0) },
            rating: row.rating,
            reviewCount: row.reviewCount,
            coverMen: row.coverMen,
            coverWomen: row.coverWomen,
            openTime: Self.formatTime24to12(row.openTime),
            closeTime: Self.formatTime24to12(row.closeTime),
            avgSpend: Self.formatAvgSpend(row.avgSpend),
            // Antes inventaba "Smart casual"/"Street parking available" cuando
            // la base no tenía el dato — eso es exactamente lo que la regla
            // "nunca fabricar datos de venue" prohíbe. Si Google/Supabase no
            // lo tienen, se muestra vacío en la UI, no un valor inventado.
            dressCode: row.dressCode.flatMap { $0.isEmpty ? nil : $0 } ?? "",
            parking: row.parking.flatMap { $0.isEmpty ? nil : $0 } ?? "",
            crowdLevel: Self.mapCrowdLevel(row.crowdLevel),
            bestArrivalTime: row.bestArrivalTime ?? "",
            peakHours: row.peakHours ?? "",
            popularDrinks: Self.mapPopularDrinks(row.popularDrinks),
            upcomingEvents: events,
            tags: Self.deriveTags(from: row),
            emoji: row.emoji ?? "🍸",
            instagramHandle: row.instagramHandle,
            isTrending: row.isTrending ?? false,
            hasHappyHour: row.happyHourUntil != nil,
            happyHourUntil: row.happyHourUntil,
            isOpenNow: Self.computeIsOpenNow(openTime: row.openTime, closeTime: row.closeTime),
            photoUrls: row.imageUrl.map { [$0] } ?? [],
            editorial: Self.buildEditorial(hook: row.hook, description: row.description),
            phone: row.phone,
            website: row.website,
            slug: row.slug,
            amenities: VenueAmenities(
                wheelchairAccessible: row.wheelchairAccessible,
                outdoorSeating: row.outdoorSeating,
                goodForGroups: row.goodForGroups,
                goodForWatchingSports: row.goodForWatchingSports,
                hasLiveMusic: row.hasLiveMusic,
                reservable: row.reservable,
                servesVegetarianFood: row.servesVegetarianFood,
                restroom: row.restroom
            ),
            experienceTags: experienceTags,
            city: row.city,
            country: row.country,
            timezoneId: row.timezone
        )
    }

    private static func mapType(_ dbType: String) -> VenueType {
        switch dbType.lowercased() {
        case "club": return .club
        case "rooftop": return .rooftop
        case "bar": return .bar
        case "lounge": return .lounge
        case "sports_bar": return .sportsBar
        case "restaurant": return .restaurant
        case "brewery": return .brewery
        default: return .bar
        }
    }

    private static func mapGenre(_ raw: String) -> MusicGenre? {
        switch raw.lowercased() {
        case "edm": return .edm
        case "house", "techno": return .house
        case "latin": return .latin
        case "hip_hop", "hiphop", "hip-hop": return .hipHop
        case "reggaeton": return .reggaeton
        case "pop": return .pop
        case "live": return .live
        case "jazz": return .jazz
        case "tech_house", "techhouse": return .techHouse
        case "rnb", "r&b": return .rnb
        default: return MusicGenre(rawValue: raw)
        }
    }

    private static func formatTime24to12(_ time: String) -> String {
        let parts = time.split(separator: ":")
        guard parts.count >= 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else { return time }

        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        guard let date = Calendar.current.date(from: components) else { return time }
        return formatter.string(from: date)
    }

    private static func formatAvgSpend(_ spend: Int?) -> String {
        guard let spend, spend > 0 else { return "N/A" }
        return "$\(spend)+"
    }

    private static func mapCrowdLevel(_ level: String?) -> Int {
        guard let level = level?.lowercased() else { return 3 }
        switch level {
        case "empty": return 1
        case "quiet": return 2
        case "steady": return 3
        case "busy": return 4
        case "packed": return 5
        default: return 3
        }
    }

    // Stored in Supabase as a JSON-encoded STRING (not a jsonb array), with
    // numeric prices — so we decode the raw string and parse it ourselves.
    private static func mapPopularDrinks(_ json: String?) -> [PopularDrink] {
        guard let json,
              let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }

        return arr.enumerated().compactMap { i, dict in
            guard let name = dict["name"] as? String else { return nil }
            let price: Double
            if let p = dict["price"] as? Double { price = p }
            else if let p = dict["price"] as? Int { price = Double(p) }
            else if let s = dict["price"] as? String { price = Double(s) ?? 0 }
            else { price = 0 }
            return PopularDrink(
                id: "supabase-\(i)",
                name: name,
                price: price,
                emoji: dict["emoji"] as? String ?? "🍸"
            )
        }
    }

    private static func deriveTags(from row: SupabaseVenueRow) -> [String] {
        var tags: [String] = []
        if let vibes = row.vibes { tags.append(contentsOf: vibes) }
        tags.append(row.neighborhood)
        tags.append(Self.mapType(row.type).rawValue)
        if row.isTrending ?? false { tags.append("Trending") }
        if row.happyHourUntil != nil { tags.append("Happy Hour") }
        return tags
    }

    private static func computeIsOpenNow(openTime: String, closeTime: String) -> Bool {
        VenueTimeStatus.isOpenNow(openTime: openTime, closeTime: closeTime)
    }

    private static func buildEditorial(hook: String?, description: String?) -> String? {
        let parts = [hook, description].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }
}

// MARK: - Supabase Row Types

struct SupabaseVenueRow: Codable {
    let id: UUID
    let slug: String?
    let name: String
    let type: String
    let neighborhood: String
    let address: String
    let lat: Double
    let lng: Double
    let hook: String?
    let description: String?
    let rating: Double
    let reviewCount: Int
    let coverMen: Int?
    let coverWomen: Int?
    let avgSpend: Int?
    let openTime: String
    let closeTime: String
    let happyHourUntil: String?
    let musicGenres: [String]?
    let vibes: [String]?
    let dressCode: String?
    let parking: String?
    let crowdLevel: String?
    let bestArrivalTime: String?
    let peakHours: String?
    let popularDrinks: String?
    let emoji: String?
    let imageUrl: String?
    let instagramHandle: String?
    let isTrending: Bool?
    let phone: String?
    let website: String?
    let wheelchairAccessible: Bool?
    let outdoorSeating: Bool?
    let goodForGroups: Bool?
    let goodForWatchingSports: Bool?
    let hasLiveMusic: Bool?
    let reservable: Bool?
    let servesVegetarianFood: Bool?
    let restroom: Bool?
    let city: String?
    let country: String?
    let timezone: String?
}

struct SupabaseEventRow: Codable {
    let id: UUID
    let venueId: UUID
    let title: String
    let description: String
    let startsAt: Date
    let endsAt: Date?
    let coverPrice: Int?
}

struct SupabaseExperienceTagRow: Codable {
    let venueId: UUID
    let tagId: String
    let category: String
    let confidence: TagConfidence
    let source: TagSource
    let computedAt: Date?
}
