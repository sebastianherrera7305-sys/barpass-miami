import SwiftUI

/// Persisted venue favorites. The detail-view heart was a dead @State that
/// forgot everything on dismiss — now favorites survive restarts and power
/// a "Tus favoritos" shelf on Tonight.
@MainActor
final class FavoritesStore: ObservableObject {
    static let shared = FavoritesStore()
    private static let key = "bp_favorites"

    @Published private(set) var ids: Set<String> = []

    private init() {
        if let saved = UserDefaults.standard.array(forKey: Self.key) as? [String] {
            ids = Set(saved)
        }
    }

    func isFavorite(_ venueId: String) -> Bool { ids.contains(venueId) }

    func toggle(_ venueId: String) {
        if ids.contains(venueId) { ids.remove(venueId) } else { ids.insert(venueId) }
        UserDefaults.standard.set(Array(ids), forKey: Self.key)
    }
}
