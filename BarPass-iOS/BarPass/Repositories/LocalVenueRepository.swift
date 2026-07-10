import Foundation

/// Offline fallback venue source. Used only when Supabase is unreachable —
/// returns the bundled preview venue so the UI renders instead of hanging.
/// (The original 6-venue hardcoded catalog was lost in the 2026-07-10 git
/// clean incident; real data lives in Supabase, so this thin fallback is
/// intentionally minimal.)
final actor LocalVenueRepository: VenueRepository {
    private let venues: [BarPassVenue] = [.preview]

    func getVenues() async throws -> [BarPassVenue] { venues }
    func getVenue(id: String) async throws -> BarPassVenue? { venues.first { $0.id == id } }
    func getTrendingVenues() async throws -> [BarPassVenue] { venues.filter { $0.isTrending } }
    func getOpenNowVenues() async throws -> [BarPassVenue] { venues.filter { $0.isOpenNow } }
    func getHappyHourVenues() async throws -> [BarPassVenue] { venues.filter { $0.hasHappyHour } }
    func getVenuesByNeighborhood(_ neighborhood: String) async throws -> [BarPassVenue] {
        venues.filter { $0.neighborhood == neighborhood }
    }
    func searchVenues(query: String) async throws -> [BarPassVenue] {
        guard !query.isEmpty else { return venues }
        let q = query.lowercased()
        return venues.filter {
            $0.name.lowercased().contains(q) ||
            $0.neighborhood.lowercased().contains(q) ||
            $0.tags.contains { $0.lowercased().contains(q) }
        }
    }
}
