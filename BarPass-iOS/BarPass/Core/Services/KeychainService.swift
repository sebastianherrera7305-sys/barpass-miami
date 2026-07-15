import Foundation
import Security

/// Wrapper mínimo sobre Keychain Services para secretos chicos (session
/// tokens). kSecClassGenericPassword es el patrón estándar de iOS para
/// secretos scoped a la app, sin sync a iCloud ni gate biométrico —
/// justo lo que necesita un token de sesión.
enum KeychainService {
    private static let service = "com.sebastian.barpass.auth"

    @discardableResult
    static func save(_ data: Data, forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        // Borrar cualquier valor previo primero — SecItemAdd falla con
        // errSecDuplicateItem si ya existe una entrada para esta cuenta.
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        // AfterFirstUnlock: legible en background (refresh de sesión),
        // pero cifrado hasta el primer desbloqueo del dispositivo.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func load(forKey key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    @discardableResult
    static func delete(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
