import Foundation

/// Which city's venues the user wants to see. Chosen once after the age
/// gate, persisted locally, changeable later from Profile. Mirrors
/// AgeGateService's shape: a plain enum over UserDefaults, no ObservableObject
/// needed since VenueStore/AppState own the @Published state that reacts to it.
enum SelectedCityStore {
    private static let cityKey = "bp_selected_city"

    static var selectedCity: String? {
        UserDefaults.standard.string(forKey: cityKey)
    }

    /// Posts .selectedCityChanged so any already-alive VenueStore (which
    /// lives inside MainTabView, outside this file's reach) can re-filter
    /// its already-fetched venues in place — no repository re-fetch, no
    /// direct reference needed between the two.
    static func select(_ city: String) {
        UserDefaults.standard.set(city, forKey: cityKey)
        NotificationCenter.default.post(name: .selectedCityChanged, object: city)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: cityKey)
    }
}
