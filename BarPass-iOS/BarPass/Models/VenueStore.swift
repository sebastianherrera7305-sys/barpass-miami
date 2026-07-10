import Foundation

@MainActor
final class VenueStore: ObservableObject {
    @Published var venues: [BarPassVenue] = []
    @Published var selectedNeighborhood: String? = nil
    @Published var selectedType: VenueType? = nil
    @Published var isLoading = true
    @Published var loadError: String? = nil

    private let repository: VenueRepository

    init(repository: VenueRepository = RepositoryDependencies.venue) {
        self.repository = repository
    }

    func loadVenues() async {
        isLoading = true
        loadError = nil
        do {
            venues = try await repository.getVenues()
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    var trending: [BarPassVenue]    { venues.filter { $0.isTrending } }
    var openNow:  [BarPassVenue]    { venues.filter { $0.isOpenNow } }
    var happyHour:[BarPassVenue]    { venues.filter { $0.hasHappyHour } }

    var neighborhoods: [String] {
        Array(Set(venues.map { $0.neighborhood })).sorted()
    }

    func venues(for tag: String) -> [BarPassVenue] {
        venues.filter { $0.tags.contains(tag) || $0.vibes.contains(tag) }
    }

}
