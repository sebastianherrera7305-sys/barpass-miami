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
}
