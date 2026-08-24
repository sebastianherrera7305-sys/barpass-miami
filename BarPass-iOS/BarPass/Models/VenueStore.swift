import Foundation
import Combine

@MainActor
final class VenueStore: ObservableObject {
    /// City-filtered view of allVenues — every consumer (TonightView,
    /// ExploreView, TripsListView, the scoring engines) reads this and gets
    /// the selected city automatically, with no per-view filtering needed.
    @Published var venues: [BarPassVenue] = []
    /// The city `venues` is currently filtered to, if any — exposed so views
    /// like ExploreView can react (e.g. re-center the map) when it changes,
    /// without diffing the venues array itself.
    @Published private(set) var selectedCity: String? = SelectedCityStore.selectedCity
    @Published var selectedNeighborhood: String? = nil
    @Published var selectedType: VenueType? = nil
    @Published var isLoading = true
    @Published var loadError: String? = nil
    /// When the currently-shown venue list was last confirmed fresh — nil
    /// until the first successful load. Consumers can use this to show a
    /// "updated Xm ago" hint instead of implying the data is always live.
    @Published var lastRefreshed: Date? = nil

    private let repository: VenueRepository
    /// The full, unfiltered fetch — `venues` is always derived from this.
    private var allVenues: [BarPassVenue] = []
    private var cancellables = Set<AnyCancellable>()

    init(repository: VenueRepository = RepositoryDependencies.venue) {
        self.repository = repository
        NotificationCenter.default.publisher(for: .selectedCityChanged)
            .compactMap { $0.object as? String }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] city in self?.applyCityFilter(city) }
            .store(in: &cancellables)
    }

    /// Safe to call repeatedly (foreground, reconnect, tab switch) — only
    /// shows the loading skeleton on the very first call. Later calls refresh
    /// the list in place; the repository itself decides whether that means a
    /// real network fetch or a still-fresh cache hit.
    func loadVenues() async {
        if venues.isEmpty { isLoading = true }
        loadError = nil
        do {
            allVenues = try await repository.getVenues()
            applyCityFilter(SelectedCityStore.selectedCity)
            lastRefreshed = Date()
        } catch {
            if venues.isEmpty { loadError = error.localizedDescription }
        }
        isLoading = false
    }

    /// Explicit user-initiated refresh (pull-to-refresh) — bypasses the
    /// repository's freshness window so "pull down" always means "check now".
    func forceRefresh() async {
        loadError = nil
        do {
            allVenues = try await repository.refresh()
            applyCityFilter(SelectedCityStore.selectedCity)
            lastRefreshed = Date()
        } catch {
            if venues.isEmpty { loadError = error.localizedDescription }
        }
    }

    /// nil (or a city with zero matches, e.g. before the first load
    /// finishes) shows everything rather than an empty screen.
    private func applyCityFilter(_ city: String?) {
        selectedCity = city
        guard let city, !city.isEmpty else {
            venues = allVenues
            return
        }
        let matches = allVenues.filter { $0.city == city }
        venues = matches.isEmpty ? allVenues : matches
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
