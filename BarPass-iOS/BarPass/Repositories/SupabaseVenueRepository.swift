import Foundation

final actor SupabaseVenueRepository: VenueRepository {
    private var loadedVenues: [BarPassVenue]?
    private var loadedAt: Date?

    /// How long the in-memory snapshot is trusted before a call to
    /// `getVenues()` triggers a real network fetch again. Without this, the
    /// actor cached the first launch's data for the entire process lifetime —
    /// venues, events, and trending status never updated no matter how long
    /// the app stayed open or how many times it came back from background.
    private static let freshnessWindow: TimeInterval = 10 * 60

    /// Exact columns the decoder uses — `select=*` shipped dead columns on
    /// every app launch (egress is the free-tier bottleneck).
    private static let venueColumns = "id,slug,name,type,neighborhood,address,lat,lng,hook,description,rating,review_count,cover_men,cover_women,price_tier,avg_spend,open_time,close_time,happy_hour_until,music_genres,vibes,dress_code,parking,crowd_level,best_arrival_time,peak_hours,popular_drinks,emoji,image_url,instagram_handle,is_trending,phone,website,wheelchair_accessible,outdoor_seating,good_for_groups,good_for_watching_sports,has_live_music,reservable,serves_vegetarian_food,restroom,city,country,timezone"
    private static let eventColumns = "id,venue_id,title,description,starts_at,ends_at,cover_price"
    private static let tagColumns = "venue_id,tag_id,category,confidence,source,computed_at"
    private static let ageBracketColumns = "venue_id,bracket,source,report_count"

    /// Cache en disco de la última lista real obtenida — antes el fallback
    /// sin red era 1 sola venue hardcodeada de preview (LocalVenueRepository),
    /// lo cual hacía que la app se sintiera rota sin conexión.
    private static let cacheURL: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("BarPassVenueCache.json")
    }()

    private func ensureVenues(forceRefresh: Bool = false) async throws -> [BarPassVenue] {
        if !forceRefresh,
           let venues = loadedVenues,
           let loadedAt,
           Date().timeIntervalSince(loadedAt) < Self.freshnessWindow {
            return venues
        }
        let venues = await fetchVenuesWithFallback()
        loadedVenues = venues
        loadedAt = Date()
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
        async let ageBracketRowsTask = fetchAgeBracketRows()
        let venueRows = try await venueRowsTask
        let eventRows = (try? await eventRowsTask) ?? []
        let tagRows = (try? await tagRowsTask) ?? []
        let ageBracketRows = (try? await ageBracketRowsTask) ?? []
        let eventsByVenue = Dictionary(grouping: eventRows, by: { $0.venueId.uuidString.lowercased() })
        let tagsByVenue = Dictionary(grouping: tagRows, by: { $0.venueId.uuidString.lowercased() })
        let ageBracketsByVenue = Dictionary(grouping: ageBracketRows, by: { $0.venueId.uuidString.lowercased() })

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
            let venueAgeBrackets = (ageBracketsByVenue[row.id.uuidString.lowercased()] ?? []).map {
                // The view's `source` distinguishes an informed research
                // estimate from 3+ real check-out reports. Carrying it through
                // is the point: the app must not present the two as the same
                // kind of claim.
                VenueAgeBracket(
                    id: $0.bracket,
                    source: $0.source == "user_reports" ? .userReports : .research,
                    reportCount: $0.reportCount
                )
            }
            return Self.mapRowToVenue(row, events: venueEvents, experienceTags: venueTags, ageBrackets: venueAgeBrackets)
        }
    }

    /// PostgREST caps a single response at the project's default row limit
    /// (1000 here) regardless of how many rows actually match — a plain GET
    /// silently truncates the catalog rather than erroring. venues has grown
    /// past that (1839+ rows across all cities), so this pages through with
    /// Range until a page comes back short of pageSize.
    private func fetchVenueRows() async throws -> [SupabaseVenueRow] {
        let pageSize = 1000
        var allRows: [SupabaseVenueRow] = []
        var offset = 0

        // Public-read table (RLS: "to anon, authenticated using (true)") —
        // anon key doubles as bearer, same pattern as every other
        // public-catalog repository.
        while true {
            let request = try SupabaseRESTClient.request(
                "GET", path: "venues",
                queryItems: [
                    URLQueryItem(name: "select", value: Self.venueColumns),
                    // Two different questions, two different columns:
                    // business_status answers "does this place still exist"
                    // (Google Places), excluded_reason answers "should it be
                    // in a nightlife app at all" (see
                    // barpass-v2/supabase/venue_exclusions.sql — airport VIP
                    // lounges, a cinema, smoke shops, venues 40km+ outside
                    // Miami). Both were present in the catalogue and neither
                    // was ever filtered, which is why results included places
                    // nobody could actually go out to.
                    URLQueryItem(name: "excluded_reason", value: "is.null"),
                    // NOT a plain `not.eq`: in SQL, `business_status <>
                    // 'CLOSED_PERMANENTLY'` evaluates to NULL — not true — when
                    // the column is NULL, so a bare not.eq silently dropped the
                    // 171 venues Google enrichment never reached. Missing data
                    // must never read as "closed".
                    URLQueryItem(name: "or", value: "(business_status.is.null,business_status.neq.CLOSED_PERMANENTLY)"),
                ],
                accessToken: SupabaseRESTClient.anonKey,
                extraHeaders: ["Range": "\(offset)-\(offset + pageSize - 1)"]
            )
            let data = try await SupabaseRESTClient.send(request)
            let page = try SupabaseRESTClient.decoder.decode([SupabaseVenueRow].self, from: data)
            allRows.append(contentsOf: page)
            if page.count < pageSize { break }
            offset += pageSize
        }

        return allRows
    }

    private func fetchEventRows() async throws -> [SupabaseEventRow] {
        try await publicGet("events", columns: Self.eventColumns)
    }

    private func fetchExperienceTagRows() async throws -> [SupabaseExperienceTagRow] {
        try await publicGet("venue_experience_tags", columns: Self.tagColumns)
    }

    private func fetchAgeBracketRows() async throws -> [SupabaseAgeBracketRow] {
        // venue_age_effective (venue_age_reports.sql): real user checkout
        // reports win per-bracket once there are 3+ of them, otherwise
        // falls back to venue_age_brackets (Kimi research) for that bracket
        // — never the raw research table alone.
        try await publicGet("venue_age_effective", columns: Self.ageBracketColumns)
    }

    private func publicGet<T: Decodable>(_ path: String, columns: String) async throws -> [T] {
        let request = try SupabaseRESTClient.request(
            "GET", path: path, queryItems: [URLQueryItem(name: "select", value: columns)],
            accessToken: SupabaseRESTClient.anonKey
        )
        let data = try await SupabaseRESTClient.send(request)
        return try SupabaseRESTClient.decoder.decode([T].self, from: data)
    }

    // MARK: - VenueRepository

    func getVenues() async throws -> [BarPassVenue] {
        try await ensureVenues()
    }

    func refresh() async throws -> [BarPassVenue] {
        try await ensureVenues(forceRefresh: true)
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

    private static func mapRowToVenue(_ row: SupabaseVenueRow, events: [VenueEvent], experienceTags: [ExperienceTag] = [], ageBrackets: [VenueAgeBracket] = []) -> BarPassVenue {
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
            priceTier: PriceTier(rawSupabaseValue: row.priceTier),
            openTime: Self.formatTime24to12(row.openTime),
            closeTime: Self.formatTime24to12(row.closeTime),
            avgSpend: Self.formatAvgSpend(row.avgSpend, priceTier: row.priceTier),
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
            ageBrackets: ageBrackets,
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
        case "house": return .house
        case "tech_house", "techhouse": return .techHouse
        case "techno": return .techno
        case "disco", "nu_disco", "nudisco": return .disco
        case "latin": return .latin
        case "salsa": return .salsa
        case "bachata": return .bachata
        case "reggaeton": return .reggaeton
        case "hip_hop", "hiphop", "hip-hop": return .hipHop
        case "rnb", "r&b": return .rnb
        case "soul", "motown": return .soul
        case "funk": return .funk
        case "pop": return .pop
        case "live": return .live
        case "jazz": return .jazz
        case "blues": return .blues
        case "country", "honky_tonk", "bluegrass": return .country
        case "americana", "roots", "folk", "singer_songwriter": return .americana
        case "rock", "punk", "metal", "alternative", "indie": return .rock
        case "goth", "industrial", "darkwave", "ebm", "new_wave", "post_punk": return .goth
        case "reggae", "ska": return .reggae
        case "dancehall", "bashment": return .dancehall
        case "afrobeats", "afrobeat", "afro_house", "amapiano": return .afrobeats
        case "tejano", "conjunto", "regional_mexicano", "banda", "corridos", "norteno": return .tejano
        // Latin styles with no case of their own resolve UP to `latin` rather
        // than being dropped. Losing "cumbia" entirely is worse than showing
        // it as Latin; showing it as Salsa would be a different lie.
        case "merengue", "vallenato", "cumbia", "dembow": return .latin
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

    /// A real per-venue `avg_spend` always wins. When it's unset (true for
    /// every venue added via add-venues.ts — Google Places has no per-drink
    /// spend field to pull), fall back to a range derived from the venue's
    /// real Google `price_tier` instead of showing "N/A" for 1,600+ venues.
    /// The $ ranges are Google's own published price-level convention
    /// (Google Business Profile help center), not a per-venue guess — the
    /// input (price_tier) is real, only the mapping to a dollar range is
    /// a standard convention applied to it.
    /// price_tier is a real, coarse 1-4 signal when present, but mapping it
    /// to a specific dollar range ("$20–35") presented it as a fact known
    /// about THIS venue when it was really a generic bucket guess — exactly
    /// the "looks real, isn't" placeholder this app's data rules forbid.
    /// N/A when the real per-venue avg_spend isn't known, full stop.
    private static func formatAvgSpend(_ spend: Int?, priceTier: Int?) -> String {
        if let spend, spend > 0 { return "$\(spend)+" }
        return "N/A"
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

    private static func mapPopularDrinks(_ field: SupabasePopularDrinksField?) -> [PopularDrink] {
        guard let field else { return [] }
        return field.items.enumerated().map { i, item in
            PopularDrink(id: "supabase-\(i)", name: item.name, price: item.price ?? 0, emoji: item.emoji ?? "🍸")
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
    let priceTier: Int?
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
    let popularDrinks: SupabasePopularDrinksField?
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

struct SupabasePopularDrinkItem: Codable {
    let name: String
    let price: Double?
    let emoji: String?

    enum CodingKeys: String, CodingKey { case name, price, emoji }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        emoji = try container.decodeIfPresent(String.self, forKey: .emoji)
        if let d = try? container.decode(Double.self, forKey: .price) {
            price = d
        } else if let s = try? container.decode(String.self, forKey: .price) {
            price = Double(s)
        } else {
            price = nil
        }
    }
}

/// popular_drinks is a jsonb column, but rows written by different loaders
/// over time disagree on shape: some store the literal array, others store
/// a JSON-encoded STRING containing that array (double-encoded). A plain
/// `String?` or `[Item]?` decode throws on whichever shape it doesn't
/// expect — this accepts both so one malformed row can't break the whole
/// venues fetch and silently fall back to fake preview data.
struct SupabasePopularDrinksField: Codable {
    let items: [SupabasePopularDrinkItem]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let arr = try? container.decode([SupabasePopularDrinkItem].self) {
            items = arr
        } else if let str = try? container.decode(String.self),
                  let data = str.data(using: .utf8),
                  let arr = try? JSONDecoder().decode([SupabasePopularDrinkItem].self, from: data) {
            items = arr
        } else {
            items = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(items)
    }
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

struct SupabaseAgeBracketRow: Codable {
    let venueId: UUID
    let bracket: String
    /// "kimi_research" or "user_reports" — see venue_age_effective.
    let source: String
    /// Only non-nil when `source` is "user_reports".
    let reportCount: Int?
}
