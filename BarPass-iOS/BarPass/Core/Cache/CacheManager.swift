import Foundation
import WebKit

@MainActor
final class CacheManager {
    static let shared = CacheManager()

    private init() {
        configureURLCache()
    }

    private func configureURLCache() {
        // 100 MB memory, 500 MB disk
        let cache = URLCache(memoryCapacity: 100 * 1024 * 1024,
                            diskCapacity:   500 * 1024 * 1024)
        URLCache.shared = cache
    }

    func clearWebCache() async {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let since = Date(timeIntervalSince1970: 0)
        await WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: since)
    }

    // Persist user session key between app launches
    func saveSession(_ token: String) {
        UserDefaults.standard.set(token, forKey: "bp_session_token")
    }

    func loadSession() -> String? {
        UserDefaults.standard.string(forKey: "bp_session_token")
    }

    func clearSession() {
        UserDefaults.standard.removeObject(forKey: "bp_session_token")
    }
}
