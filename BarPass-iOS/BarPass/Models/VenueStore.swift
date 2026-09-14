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
    ///
    /// Since 2026-09-13 this holds only the cities actually fetched (the
    /// selected one, plus any visited earlier in the session) — NOT the whole
    /// 23-city catalogue. `coveredCities` therefore can no longer be derived
    /// from it; see below.
    private var allVenues: [BarPassVenue] = []
    /// Every city we actually have venues for. A screen that offers to send
    /// someone into a city's nightlife must check this first — 24 of the 47
    /// universities point at a city with zero venues (Durham, Tucson,
    /// Orlando...), and "Nightlife in X" dropped them onto an empty Explore
    /// that then reset their city. TestFlight: "the part that says nightlife
    /// in Coral Gables does not work and it's the same for all the colleges
    /// and all the 23 cities".
    ///
    /// Sourced from the repository's dedicated city index
    /// (`getCityCounts()`, a ~42KB `select=city` query), NOT from
    /// `allVenues` — which is now one city's worth of venues and would
    /// answer "no nightlife" for the other 22.
    @Published private(set) var coveredCities: Set<String> = []
    /// city -> venue count, same source. The city picker reads this instead of
    /// counting a full catalogue it no longer downloads.
    @Published private(set) var cityCounts: [String: Int] = [:]
    private var cancellables = Set<AnyCancellable>()

    init(repository: VenueRepository = RepositoryDependencies.venue) {
        self.repository = repository
        NotificationCenter.default.publisher(for: .selectedCityChanged)
            .compactMap { $0.object as? String }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] city in
                guard let self else { return }
                // Do NOT treat "we have no venues for this city yet" as a
                // stale-city-preference reset here: with city-scoped fetches
                // that is the NORMAL state right after switching. Show the
                // loading state and go fetch that city; the reset check only
                // runs once a fetch has actually come back.
                self.applyCityFilter(city)
                if self.venues.isEmpty { Task { await self.loadVenues() } }
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .venueCityIndexRefreshed)
            .compactMap { $0.object as? [String: Int] }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] counts in self?.applyCityCounts(counts) }
            .store(in: &cancellables)
        // Cache-first launch: the repository answers instantly from disk (or
        // the selected city alone) and refreshes the full catalog behind it.
        // When that lands, swap it in without a loading state.
        NotificationCenter.default.publisher(for: .venueCatalogRefreshed)
            .compactMap { $0.object as? [BarPassVenue] }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] fresh in
                guard let self else { return }
                self.allVenues = fresh
                self.applyCityFilter(SelectedCityStore.selectedCity, afterFetch: true)
                self.lastRefreshed = Date()
            }
            .store(in: &cancellables)
    }

    /// Safe to call repeatedly (foreground, reconnect, tab switch) — only
    /// shows the loading skeleton on the very first call. Later calls refresh
    /// the list in place; the repository itself decides whether that means a
    /// real network fetch or a still-fresh cache hit.
    func loadVenues() async {
        if venues.isEmpty { isLoading = true }
        loadError = nil
        // Both in flight at once: the city index is a separate, tiny
        // (~42KB, usually disk-cached) query, and it must land BEFORE the
        // filter runs — otherwise a city that is legitimately covered but
        // whose fetch failed would look like a stale preference and get
        // reset out from under the user.
        async let countsTask = try? repository.getCityCounts()
        do {
            let fetched = try await repository.getVenues()
            if let counts = await countsTask, !counts.isEmpty { applyCityCounts(counts) }
            allVenues = fetched
            applyCityFilter(SelectedCityStore.selectedCity, afterFetch: true)
            lastRefreshed = Date()
        } catch {
            if let counts = await countsTask, !counts.isEmpty { applyCityCounts(counts) }
            if venues.isEmpty { loadError = error.localizedDescription }
        }
        isLoading = false
    }

    /// Cheap and cached (disk + 24h in-memory), so calling it after every load
    /// is fine — it is a `select=city` read, not a catalogue read.
    func loadCityIndex() async {
        guard let counts = try? await repository.getCityCounts(), !counts.isEmpty else { return }
        applyCityCounts(counts)
    }

    private func applyCityCounts(_ counts: [String: Int]) {
        cityCounts = counts
        coveredCities = Set(counts.keys)
    }

    /// Explicit user-initiated refresh (pull-to-refresh) — bypasses the
    /// repository's freshness window so "pull down" always means "check now".
    func forceRefresh() async {
        loadError = nil
        do {
            allVenues = try await repository.refresh()
            applyCityFilter(SelectedCityStore.selectedCity, afterFetch: true)
            lastRefreshed = Date()
        } catch {
            if venues.isEmpty { loadError = error.localizedDescription }
        }
    }

    /// nil (before a city is ever chosen, or before the first load finishes)
    /// shows everything — there's genuinely no filter to apply yet.
    ///
    /// A NON-nil city that matches zero venues is a different situation, and
    /// used to be treated the same way ("show everything") — that silently
    /// dumped all ~1846 venues across all 23 cities into what the user
    /// expected to be one city's feed. Root cause: a `bp_selected_city`
    /// value that no longer exact-matches any venue's `city` column (stale
    /// value from before the multi-city expansion, a spelling change
    /// server-side, etc.) stays non-nil forever, so `proceedPastAgeGate()`'s
    /// `selectedCity == nil` check never re-triggers the city picker either
    /// — every screen quietly showed the entire catalog mixed together,
    /// looking like "random" broken/inconsistent cards city to city. Now:
    /// clear the stale preference so the picker is forced to reappear (via
    /// AppState's existing nil-check) instead of ever silently mixing
    /// cities, and show nothing in the meantime rather than a wrong catalog.
    private func applyCityFilter(_ city: String?, afterFetch: Bool = false) {
        guard let city, !city.isEmpty else {
            selectedCity = city
            venues = allVenues
            return
        }
        let matches = allVenues.filter { $0.city == city }
        if matches.isEmpty, afterFetch {
            // The city index is the authoritative answer to "does this city
            // exist in the catalogue"; fall back to the old heuristic only
            // when we don't have it (first ever launch, offline).
            let indexSaysUnknownCity = !coveredCities.isEmpty && !coveredCities.contains(city)
            let noIndexButSomethingLoaded = coveredCities.isEmpty && !allVenues.isEmpty
            if indexSaysUnknownCity || noIndexButSomethingLoaded {
                SelectedCityStore.reset()
                selectedCity = nil
                venues = []
                return
            }
        }
        selectedCity = city
        venues = matches
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
