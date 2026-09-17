import Foundation

final actor SupabaseVenueRepository: VenueRepository {
    /// Venues we have, keyed by the city they were fetched for. `""` is the
    /// unscoped fetch, used only before a city has ever been chosen.
    ///
    /// 2026-09-13: every launch and every refresh used to download the WHOLE
    /// 23-city catalogue (1,899 rows × 45 columns, ~2.7MB in two sequential
    /// pages) plus events/tags/age-brackets/price-stats for all 23 cities, in
    /// order to render the ~160 venues of ONE city. Inside a club on contended
    /// LTE that saturates the connection and starves image loads, the AI chat
    /// and check-in — the #1 reported complaint ("too slow inside the club").
    /// Now each city is fetched on its own (~250KB) and KEPT here, so
    /// switching back to a city already visited costs nothing.
    private var venuesByCity: [String: [BarPassVenue]] = [:]
    private var loadedAtByCity: [String: Date] = [:]
    private var refreshingCities: Set<String> = []
    private static let allCitiesKey = ""

    /// How long the in-memory snapshot is trusted before a call to
    /// `getVenues()` triggers a real network fetch again. Without this, the
    /// actor cached the first launch's data for the entire process lifetime —
    /// venues, events, and trending status never updated no matter how long
    /// the app stayed open or how many times it came back from background.
    private static let freshnessWindow: TimeInterval = 10 * 60

    /// Exact columns the decoder uses — `select=*` shipped dead columns on
    /// every app launch (egress is the free-tier bottleneck).
    private static let venueColumns = "id,slug,name,type,neighborhood,address,lat,lng,hook,description,rating,review_count,cover_men,cover_women,price_tier,avg_spend,open_time,close_time,hours,happy_hour_until,music_genres,vibes,dress_code,parking,crowd_level,best_arrival_time,peak_hours,popular_drinks,emoji,image_url,instagram_handle,is_trending,phone,website,wheelchair_accessible,outdoor_seating,good_for_groups,good_for_watching_sports,has_live_music,reservable,serves_vegetarian_food,restroom,city,country,timezone"
    private static let eventColumns = "id,venue_id,title,description,starts_at,ends_at,cover_price,student_eligible,student_price_cents"
    private static let tagColumns = "venue_id,tag_id,category,confidence,source,computed_at"
    private static let ageBracketColumns = "venue_id,bracket,source,report_count"

    /// Cache en disco de la última lista real obtenida — antes el fallback
    /// sin red era 1 sola venue hardcodeada de preview (LocalVenueRepository),
    /// lo cual hacía que la app se sintiera rota sin conexión.
    ///
    /// One file PER CITY (plus one for the city index) instead of a single
    /// whole-catalogue blob: a city-scoped world must never be able to write
    /// one city's venues into a file the next launch reads back as "the whole
    /// catalogue". The legacy single file is migrated on first read below.
    private static let cacheDirectory: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("BarPassVenueCache", isDirectory: true)
        // Application Support is NOT created for us on iOS — without this the
        // old `write(to:)` silently failed on a fresh install and the offline
        // fallback never had anything to serve.
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let legacyCacheURL: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("BarPassVenueCache.json")
    }()

    private static let cityIndexCacheURL = cacheDirectory.appendingPathComponent("city-index.json")

    private static func cacheURL(forKey key: String) -> URL {
        // Cities are free text from the DB ("New York", "Washington, D.C.") —
        // never interpolate one straight into a path.
        let safe = key.isEmpty
            ? "all"
            : key.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "_" }
                 .reduce(into: "") { $0.append($1) }
        return cacheDirectory.appendingPathComponent("city-\(safe).json")
    }

    /// The single list every consumer sees: every city fetched so far, in a
    /// stable order, deduplicated by id. Callers (VenueStore) filter it down
    /// to the selected city themselves.
    private func mergedVenues() -> [BarPassVenue] {
        var seen = Set<String>()
        var out: [BarPassVenue] = []
        for key in venuesByCity.keys.sorted() {
            for venue in venuesByCity[key] ?? [] where seen.insert(venue.id).inserted {
                out.append(venue)
            }
        }
        return out
    }

    private func ensureVenues(forceRefresh: Bool = false) async throws -> [BarPassVenue] {
        let city = SelectedCityStore.selectedCity
        let key = city ?? Self.allCitiesKey

        if !forceRefresh,
           venuesByCity[key] != nil,
           let at = loadedAtByCity[key],
           Date().timeIntervalSince(at) < Self.freshnessWindow {
            return mergedVenues()
        }
        if forceRefresh {
            let venues = await fetchVenuesWithFallback(city: city)
            commit(venues, key: key)
            return mergedVenues()
        }

        // Launch path (2026-09-08). Show what we have in ~100ms, refresh the
        // selected city in the background, and hand the fresh list to
        // VenueStore via .venueCatalogRefreshed.
        if venuesByCity[key] == nil {
            migrateLegacyCacheIfNeeded()
            if let cached = readCache(key: key), !cached.isEmpty {
                venuesByCity[key] = cached
                scheduleBackgroundRefresh(city: city)
                return mergedVenues()
            }
        } else {
            // Freshness window expired while the app stayed open: serve the
            // stale list now, refresh behind it.
            scheduleBackgroundRefresh(city: city)
            return mergedVenues()
        }
        let venues = await fetchVenuesWithFallback(city: city)
        commit(venues, key: key)
        return mergedVenues()
    }

    private func commit(_ venues: [BarPassVenue], key: String) {
        guard !venues.isEmpty else { return }
        venuesByCity[key] = venues
        loadedAtByCity[key] = Date()
    }

    private func scheduleBackgroundRefresh(city: String?) {
        let key = city ?? Self.allCitiesKey
        guard !refreshingCities.contains(key) else { return }
        refreshingCities.insert(key)
        Task { [weak self] in
            guard let self else { return }
            let venues = await self.fetchVenuesWithFallback(city: city)
            await self.commitBackgroundRefresh(venues, key: key)
        }
    }

    private func commitBackgroundRefresh(_ venues: [BarPassVenue], key: String) {
        refreshingCities.remove(key)
        guard !venues.isEmpty else { return }
        commit(venues, key: key)
        let merged = mergedVenues()
        Task { @MainActor in
            NotificationCenter.default.post(name: .venueCatalogRefreshed, object: merged)
        }
    }

    private func fetchVenuesWithFallback(city: String?) async -> [BarPassVenue] {
        let key = city ?? Self.allCitiesKey
        do {
            let venues = try await fetchFromSupabase(city: city)
            persistCache(venues, key: key)
            return venues
        } catch {
            #if DEBUG
            print("⚠️ SupabaseVenueRepository: fetch failed, falling back to cache. Error: \(error)")
            #endif
            migrateLegacyCacheIfNeeded()
            if let cached = readCache(key: key), !cached.isEmpty {
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

    private func persistCache(_ venues: [BarPassVenue], key: String) {
        guard let data = try? JSONEncoder().encode(venues) else { return }
        try? data.write(to: Self.cacheURL(forKey: key), options: .atomic)
    }

    private func readCache(key: String) -> [BarPassVenue]? {
        guard let data = try? Data(contentsOf: Self.cacheURL(forKey: key)) else { return nil }
        return try? JSONDecoder().decode([BarPassVenue].self, from: data)
    }

    private var didMigrateLegacyCache = false

    /// Installs updating from a build before the city split have one big
    /// BarPassVenueCache.json holding every city. Split it into the per-city
    /// files (so an offline first launch still has the selected city) and
    /// delete it — never read it as if it were one city's data.
    private func migrateLegacyCacheIfNeeded() {
        guard !didMigrateLegacyCache else { return }
        didMigrateLegacyCache = true
        guard let data = try? Data(contentsOf: Self.legacyCacheURL),
              let venues = try? JSONDecoder().decode([BarPassVenue].self, from: data) else { return }
        for (city, cityVenues) in Dictionary(grouping: venues.filter { $0.city != nil }, by: { $0.city! }) {
            persistCache(cityVenues, key: city)
        }
        try? FileManager.default.removeItem(at: Self.legacyCacheURL)
    }

    private func fetchFromSupabase(city: String? = nil) async throws -> [BarPassVenue] {
        // Venues first, then everything else scoped to exactly those venue
        // ids. None of events / venue_experience_tags / venue_age_effective /
        // venue_price_stats has a `city` column (they all key off venue_id),
        // so the ids ARE the city scope — no column invented, and no 155KB of
        // another city's tags on the wire.
        let venueRows = try await fetchVenueRows(city: city)
        let venueIds = city == nil ? nil : venueRows.map(\.id)

        async let eventRowsTask = fetchEventRows(venueIds: venueIds)
        async let tagRowsTask = fetchExperienceTagRows(venueIds: venueIds)
        async let ageBracketRowsTask = fetchAgeBracketRows(venueIds: venueIds)
        async let priceStatsTask = fetchPriceStatRows(venueIds: venueIds)
        let eventRows = (try? await eventRowsTask) ?? []
        let tagRows = (try? await tagRowsTask) ?? []
        let ageBracketRows = (try? await ageBracketRowsTask) ?? []
        // Optional by design: the view doesn't exist until
        // venue_price_reports.sql has been run — a 404 here must never
        // block the catalog.
        let priceRows = (try? await priceStatsTask) ?? []
        let priceByVenue = Dictionary(priceRows.map { ($0.venueId.uuidString.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
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
                    endDate: event.endsAt,
                    studentEligible: event.studentEligible ?? false,
                    studentPrice: event.studentPriceCents.map { Double($0) / 100 }
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
            var venue = Self.mapRowToVenue(row, events: venueEvents, experienceTags: venueTags, ageBrackets: venueAgeBrackets)
            if let stat = priceByVenue[row.id.uuidString.lowercased()] {
                venue.reportedDrinkPrice = VenueReportedPrice(medianDollars: Double(stat.medianDrinkCents) / 100, reportCount: stat.reportCount)
            }
            return venue
        }
    }

    private func fetchPriceStatRows(venueIds: [UUID]?) async throws -> [SupabasePriceStatRow] {
        try await publicGet("venue_price_stats", columns: "venue_id,median_drink_cents,report_count", venueIds: venueIds)
    }

    /// PostgREST caps a single response at the project's default row limit
    /// (1000 here) regardless of how many rows actually match — a plain GET
    /// silently truncates the catalog rather than erroring. venues has grown
    /// past that (1839+ rows across all cities), so this pages through with
    /// Range until a page comes back short of pageSize.
    private func fetchVenueRows(city: String? = nil) async throws -> [SupabaseVenueRow] {
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
                    // Paginar sin ORDER BY es pedirle a Postgres un orden que
                    // no promete: entre dos páginas puede devolver la misma
                    // fila dos veces y saltearse otra, sin error y sin que
                    // nada parezca roto. `id` es único, así que la ventana es
                    // estable aunque el catálogo cambie entre páginas.
                    URLQueryItem(name: "order", value: "id"),
                ] + (city.map { [URLQueryItem(name: "city", value: "eq.\($0)")] } ?? []),
                accessToken: SupabaseRESTClient.anonKey,
                extraHeaders: ["Range": "\(offset)-\(offset + pageSize - 1)"],
                timeout: Self.requestTimeout
            )
            let data = try await SupabaseRESTClient.send(request)
            let page = try SupabaseRESTClient.decoder.decode([SupabaseVenueRow].self, from: data)
            allRows.append(contentsOf: page)
            if page.count < pageSize { break }
            offset += pageSize
        }

        return allRows
    }

    private func fetchEventRows(venueIds: [UUID]?) async throws -> [SupabaseEventRow] {
        try await publicGet("events", columns: Self.eventColumns, venueIds: venueIds)
    }

    private func fetchExperienceTagRows(venueIds: [UUID]?) async throws -> [SupabaseExperienceTagRow] {
        try await publicGet("venue_experience_tags", columns: Self.tagColumns, venueIds: venueIds)
    }

    private func fetchAgeBracketRows(venueIds: [UUID]?) async throws -> [SupabaseAgeBracketRow] {
        // venue_age_effective (venue_age_reports.sql): real user checkout
        // reports win per-bracket once there are 3+ of them, otherwise
        // falls back to venue_age_brackets (Kimi research) for that bracket
        // — never the raw research table alone.
        // NOTE: query the VIEW, never the underlying venue_age_brackets table
        // — the table has no report_count column and the decode would fail.
        try await publicGet("venue_age_effective", columns: Self.ageBracketColumns, venueIds: venueIds)
    }

    /// Pages with `Range`, for the same reason `fetchVenueRows()` does: a plain
    /// GET is silently truncated at PostgREST's 1000-row cap. This had no
    /// paging at all, and venue_experience_tags is already at 787 rows — it
    /// would have crossed the cap with no error and no empty result, just
    /// quietly worse recommendations for whatever fell off the end.
    ///
    /// `venueIds` (nil = every city, as before) scopes the read to the loaded
    /// city's venues via `venue_id=in.(…)`. The ids are sent in chunks so the
    /// URL can't grow unbounded — a whole city at once would be a ~6KB query
    /// string today and worse as cities grow.
    /// Chunk size for `venue_id=in.(…)`. A UUID is 36 chars plus a comma, so
    /// 200 ids is ~7.4KB of query string — inside every proxy's URL limit with
    /// room to spare, and it turns a 161-venue city from 3 round trips per
    /// table into 1.
    /// Per-request deadline for catalogue reads. URLSession defaults to 60s,
    /// and the launch path issues several requests, so a stalled connection
    /// used to mean minutes of grey skeleton. 12s is far longer than a healthy
    /// call (measured 0.25-1.4s) and short enough that failing over to the
    /// disk cache still feels like a launch.
    private static let requestTimeout: TimeInterval = 12

    private static let idChunkSize = 200

    private func publicGet<T: Decodable & Sendable>(_ path: String, columns: String, venueIds: [UUID]? = nil) async throws -> [T] {
        guard let venueIds else { return try await publicGetPaged(path, columns: columns, filter: nil) }
        // An empty city (nothing matched) has nothing to join against —
        // `in.()` is a syntax error, not an empty result.
        guard !venueIds.isEmpty else { return [] }

        let chunks = stride(from: 0, to: venueIds.count, by: Self.idChunkSize)
            .map { Array(venueIds[$0..<min($0 + Self.idChunkSize, venueIds.count)]) }

        // Concurrently, not one after another. Scoping these four tables to the
        // city's venue ids (2026-09-13) was right for bytes but wrong for round
        // trips: at 80 ids a chunk it turned 4 unscoped requests into 12
        // sequential ones, and on a contended connection every one of those
        // waits out the full per-request timeout before the next even starts.
        // That is what made the feed sit on a skeleton forever.
        return try await withThrowingTaskGroup(of: [T].self) { group in
            for chunk in chunks {
                group.addTask {
                    let list = chunk.map { $0.uuidString.lowercased() }.joined(separator: ",")
                    return try await self.publicGetPaged(
                        path, columns: columns,
                        filter: URLQueryItem(name: "venue_id", value: "in.(\(list))"))
                }
            }
            var rows: [T] = []
            for try await page in group { rows += page }
            return rows
        }
    }

    private func publicGetPaged<T: Decodable & Sendable>(_ path: String, columns: String, filter: URLQueryItem?) async throws -> [T] {
        let pageSize = 1000
        var allRows: [T] = []
        var offset = 0

        while true {
            let request = try SupabaseRESTClient.request(
                "GET", path: path,
                // Mismo motivo que en fetchVenueRows: sin `order` la
                // paginación puede repetir una fila y perder otra en silencio.
                queryItems: [URLQueryItem(name: "select", value: columns),
                             URLQueryItem(name: "order", value: "venue_id")] + (filter.map { [$0] } ?? []),
                accessToken: SupabaseRESTClient.anonKey,
                extraHeaders: ["Range": "\(offset)-\(offset + pageSize - 1)"],
                timeout: Self.requestTimeout
            )
            let data = try await SupabaseRESTClient.send(request)
            let page = try SupabaseRESTClient.decoder.decode([T].self, from: data)
            allRows.append(contentsOf: page)
            if page.count < pageSize { break }
            offset += pageSize
        }

        return allRows
    }

    // MARK: - City index

    /// Which cities have venues, and how many. ~42KB over two pages
    /// (`select=city` only) against 2.7MB for the catalogue it replaces.
    ///
    /// This exists because `coveredCities` used to be derived from the venue
    /// list itself (`Set(allVenues.compactMap(\.city))`). With a city-scoped
    /// fetch that would collapse to the one loaded city, and the universities
    /// screens — which ask "does city X have any nightlife" before offering to
    /// send someone there — would have regressed to the TestFlight bug
    /// "nightlife in Coral Gables does not work ... same for all the colleges".
    private var cityIndex: [String: Int]?
    private var cityIndexLoadedAt: Date?
    private var refreshingCityIndex = false
    /// Cities are added by a seeding script, not by users — a day is plenty.
    private static let cityIndexFreshnessWindow: TimeInterval = 24 * 60 * 60

    func getCityCounts() async throws -> [String: Int] {
        if let cityIndex, let at = cityIndexLoadedAt,
           Date().timeIntervalSince(at) < Self.cityIndexFreshnessWindow {
            return cityIndex
        }
        if let stale = cityIndex {
            scheduleCityIndexRefresh()
            return stale
        }
        if let cached = readCityIndexCache(), !cached.isEmpty {
            cityIndex = cached
            scheduleCityIndexRefresh()
            return cached
        }
        let fresh = try await fetchCityCounts()
        cityIndex = fresh
        cityIndexLoadedAt = Date()
        persistCityIndex(fresh)
        return fresh
    }

    private func scheduleCityIndexRefresh() {
        guard !refreshingCityIndex else { return }
        refreshingCityIndex = true
        Task { [weak self] in
            guard let self else { return }
            let counts = try? await self.fetchCityCounts()
            await self.commitCityIndexRefresh(counts)
        }
    }

    private func commitCityIndexRefresh(_ counts: [String: Int]?) {
        refreshingCityIndex = false
        guard let counts, !counts.isEmpty else { return }
        cityIndex = counts
        cityIndexLoadedAt = Date()
        persistCityIndex(counts)
        Task { @MainActor in
            NotificationCenter.default.post(name: .venueCityIndexRefreshed, object: counts)
        }
    }

    private func fetchCityCounts() async throws -> [String: Int] {
        let pageSize = 1000
        var counts: [String: Int] = [:]
        var offset = 0
        while true {
            let request = try SupabaseRESTClient.request(
                "GET", path: "venues",
                queryItems: [
                    URLQueryItem(name: "select", value: "city"),
                    // Same two filters as the catalogue read — a city whose
                    // only rows are excluded or permanently closed must not
                    // count as covered.
                    URLQueryItem(name: "excluded_reason", value: "is.null"),
                    URLQueryItem(name: "or", value: "(business_status.is.null,business_status.neq.CLOSED_PERMANENTLY)"),
                ],
                accessToken: SupabaseRESTClient.anonKey,
                extraHeaders: ["Range": "\(offset)-\(offset + pageSize - 1)"],
                timeout: Self.requestTimeout
            )
            let data = try await SupabaseRESTClient.send(request)
            let page = try SupabaseRESTClient.decoder.decode([SupabaseCityRow].self, from: data)
            for row in page {
                guard let city = row.city, !city.isEmpty else { continue }
                counts[city, default: 0] += 1
            }
            if page.count < pageSize { break }
            offset += pageSize
        }
        return counts
    }

    private func persistCityIndex(_ counts: [String: Int]) {
        guard let data = try? JSONEncoder().encode(counts) else { return }
        try? data.write(to: Self.cityIndexCacheURL, options: .atomic)
    }

    private func readCityIndexCache() -> [String: Int]? {
        guard let data = try? Data(contentsOf: Self.cityIndexCacheURL) else { return nil }
        return try? JSONDecoder().decode([String: Int].self, from: data)
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
            weeklyHours: row.hours,
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
            isOpenNow: Self.computeIsOpenNow(weekly: row.hours, openTime: row.openTime, closeTime: row.closeTime),
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
        case "afrobeats", "afrobeat", "afro_house": return .afrobeats
        case "amapiano": return .amapiano
        case "soca", "calypso": return .soca
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
        // A drink with no price is dropped, not shown as "$0". Absence must never
        // render as a value — avg_spend = 0 showed as a confident "$0" on 1,665
        // venues before that rule existed, and VenueDetailView prints "$%.0f".
        return field.items.enumerated().compactMap { i, item in
            guard let price = item.price, price > 0 else { return nil }
            return PopularDrink(id: "supabase-\(i)", name: item.name, price: price, emoji: item.emoji ?? "🍸")
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

    /// The "Open" badge. Prefers the real weekly schedule; the single dayless
    /// pair is only a fallback for rows Google has no hours for. Showing a
    /// venue as open on a night it is shut is worse than showing nothing.
    private static func computeIsOpenNow(weekly: [VenueDayHours]?, openTime: String, closeTime: String) -> Bool {
        if let weekly, !weekly.isEmpty {
            let now = VenueTimeStatus.weekdayAndMinute(Date())
            return VenueTimeStatus.isOpen(weekly, atMinute: now.minute, weekday: now.weekday)
        }
        return VenueTimeStatus.isOpenNow(openTime: openTime, closeTime: closeTime)
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
    let hours: [VenueDayHours]?
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
    let studentEligible: Bool?
    let studentPriceCents: Int?
}

struct SupabaseExperienceTagRow: Codable {
    let venueId: UUID
    let tagId: String
    let category: String
    let confidence: TagConfidence
    let source: TagSource
    let computedAt: Date?
}

/// Just the `city` column — the whole point of the covered-cities query is
/// that it costs tens of KB, not megabytes.
struct SupabaseCityRow: Codable {
    let city: String?
}

struct SupabasePriceStatRow: Codable {
    let venueId: UUID
    let medianDrinkCents: Int
    let reportCount: Int
}

struct SupabaseAgeBracketRow: Codable {
    let venueId: UUID
    let bracket: String
    /// "kimi_research" or "user_reports" — see venue_age_effective.
    let source: String
    /// Only non-nil when `source` is "user_reports".
    let reportCount: Int?
}
