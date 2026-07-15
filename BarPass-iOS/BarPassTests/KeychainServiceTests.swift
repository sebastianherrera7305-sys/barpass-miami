import XCTest
@testable import BarPass_app

/// Cubre la migración crítica de tokens de UserDefaults a Keychain: guardar,
/// leer, borrar, y el camino de migración de AuthService.restoreSession()
/// que asegura que ninguna sesión existente se pierda con el cambio.
final class KeychainServiceTests: XCTestCase {
    private let testKey = "bp_keychain_test_key"

    override func tearDown() {
        KeychainService.delete(forKey: testKey)
        super.tearDown()
    }

    func test_save_thenLoad_returnsSameData() {
        let payload = "hola".data(using: .utf8)!
        XCTAssertTrue(KeychainService.save(payload, forKey: testKey))
        XCTAssertEqual(KeychainService.load(forKey: testKey), payload)
    }

    func test_load_withNoSavedValue_returnsNil() {
        XCTAssertNil(KeychainService.load(forKey: "bp_keychain_never_saved"))
    }

    func test_save_overwritesPreviousValue() {
        KeychainService.save("primero".data(using: .utf8)!, forKey: testKey)
        KeychainService.save("segundo".data(using: .utf8)!, forKey: testKey)
        XCTAssertEqual(KeychainService.load(forKey: testKey), "segundo".data(using: .utf8)!)
    }

    func test_delete_removesValue() {
        KeychainService.save("dato".data(using: .utf8)!, forKey: testKey)
        XCTAssertTrue(KeychainService.delete(forKey: testKey))
        XCTAssertNil(KeychainService.load(forKey: testKey))
    }

    func test_delete_whenNothingSaved_stillSucceeds() {
        // errSecItemNotFound cuenta como éxito — logout no debe fallar
        // solo porque nunca hubo sesión guardada.
        XCTAssertTrue(KeychainService.delete(forKey: "bp_keychain_never_saved"))
    }

    // MARK: - Migración desde UserDefaults (AuthService)

    func test_restoreSession_migratesLegacySessionFromUserDefaults() throws {
        let legacyKey = "bp_auth_session"
        let session = AuthSession(
            accessToken: "old-access", refreshToken: "old-refresh",
            expiresAt: Date().addingTimeInterval(3600),
            user: AuthUser(id: "u1", email: "test@barpass.app")
        )
        let data = try JSONEncoder().encode(session)

        // Simula el estado de un usuario en la versión previa a Keychain.
        UserDefaults.standard.set(data, forKey: legacyKey)
        KeychainService.delete(forKey: legacyKey)
        defer {
            KeychainService.delete(forKey: legacyKey)
            UserDefaults.standard.removeObject(forKey: legacyKey)
        }

        let restored = AuthService.shared.restoreSession()

        XCTAssertEqual(restored?.accessToken, "old-access")
        // Migración: el dato ya debe estar en Keychain...
        XCTAssertNotNil(KeychainService.load(forKey: legacyKey))
        // ...y borrado de UserDefaults, para no dejar el token viejo tirado.
        XCTAssertNil(UserDefaults.standard.data(forKey: legacyKey))
    }

    func test_signOut_clearsKeychainSession() throws {
        let legacyKey = "bp_auth_session"
        let session = AuthSession(
            accessToken: "token", refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(3600),
            user: AuthUser(id: "u1", email: nil)
        )
        KeychainService.save(try JSONEncoder().encode(session), forKey: legacyKey)

        AuthService.shared.signOut()

        XCTAssertNil(KeychainService.load(forKey: legacyKey))
        XCTAssertNil(AuthService.shared.restoreSession())
    }
}
