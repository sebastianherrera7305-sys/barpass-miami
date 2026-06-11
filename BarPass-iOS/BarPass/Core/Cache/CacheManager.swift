import Foundation
import WebKit
import Security

@MainActor
final class CacheManager {
    static let shared = CacheManager()

    private init() {
        configureURLCache()
    }

    private func configureURLCache() {
        let cache = URLCache(memoryCapacity: 100 * 1024 * 1024,
                            diskCapacity:   500 * 1024 * 1024)
        URLCache.shared = cache
    }

    func clearWebCache() async {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let since = Date(timeIntervalSince1970: 0)
        await WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: since)
    }

    // MARK: - Session token — Keychain (survives app reinstall if iCloud Keychain is on)

    func saveSession(_ token: String) {
        KeychainHelper.save(token, forKey: "bp_session_token")
    }

    func loadSession() -> String? {
        KeychainHelper.load(forKey: "bp_session_token")
    }

    func clearSession() {
        KeychainHelper.delete(forKey: "bp_session_token")
    }
}

// MARK: - Keychain helper (available across the whole module)

enum KeychainHelper {
    private static let service = "io.barpass.app"

    static func save(_ value: String, forKey key: String) {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecValueData:   data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(forKey key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      service,
            kSecAttrAccount:      key,
            kSecReturnData:       kCFBooleanTrue!,
            kSecMatchLimit:       kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(forKey key: String) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
