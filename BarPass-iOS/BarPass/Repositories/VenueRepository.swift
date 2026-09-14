/// VenueRepository defines how the app reads venue data.
/// The store layer calls these methods and never knows whether venues
/// come from a local JSON file, Supabase, Google Places, or a cache.
protocol VenueRepository: Sendable {
    func getVenues() async throws -> [BarPassVenue]
    func getVenue(id: String) async throws -> BarPassVenue?
    func getTrendingVenues() async throws -> [BarPassVenue]
    func getOpenNowVenues() async throws -> [BarPassVenue]
    func getHappyHourVenues() async throws -> [BarPassVenue]
    func getVenuesByNeighborhood(_ neighborhood: String) async throws -> [BarPassVenue]
    func searchVenues(query: String) async throws -> [BarPassVenue]

    /// Which cities have venues, and how many — the cheap index behind
    /// "does city X have any nightlife at all". Must NOT be derived from a
    /// venue list that is scoped to one city.
    func getCityCounts() async throws -> [String: Int]

    /// Bypasses any freshness cache and forces a real fetch — for pull-to-refresh
    /// and other explicit user-initiated refreshes. Default just calls
    /// `getVenues()`, which is correct for repositories with no cache of their own.
    func refresh() async throws -> [BarPassVenue]
}

extension VenueRepository {
    /// Correct for any repository whose `getVenues()` really does return
    /// every city (LocalVenueRepository); SupabaseVenueRepository overrides it
    /// with a dedicated `select=city` query.
    func getCityCounts() async throws -> [String: Int] {
        Dictionary(grouping: try await getVenues().compactMap(\.city)) { $0 }.mapValues(\.count)
    }

    func refresh() async throws -> [BarPassVenue] { try await getVenues() }
}
