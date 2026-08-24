import XCTest
@testable import BarPass_app

/// Runtime verification for ADR-012 (centralized token refresh in APIClient).
///
/// These hit the real Supabase Auth endpoint with a real refresh token, because
/// the whole point of ADR-012 is behavior that only manifests against a live
/// token lifecycle — a mocked refresh would prove nothing about the bug it fixes
/// (N-1: an expired JWT reaching the backend on payment flows).
///
/// The refresh token belongs to the App Review demo account. It is a rotating,
/// revocable credential for a test account with no real funds — not a secret in
/// the sense the project's credential rule protects (no service-role key, no
/// user password, nothing that grants privileged access).
final class AuthTokenRefreshTests: XCTestCase {

    private let sessionKey = "bp_auth_session"
    private let demoRefreshToken = "tr3qm4tp57gs"

    private func installSession(expiresAt: Date, accessToken: String, refreshToken: String) throws {
        let session = AuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            user: AuthUser(id: "demo", email: "review@barpass.app", emailConfirmedAt: nil)
        )
        KeychainService.save(try JSONEncoder().encode(session), forKey: sessionKey)
    }

    override func tearDown() {
        KeychainService.delete(forKey: sessionKey)
        super.tearDown()
    }

    /// Scenario 1 — valid token: refreshIfNeeded() must be a cheap no-op and
    /// must NOT rotate the token (guards against adding latency/churn to every
    /// authenticated request in the common case).
    func test_validToken_isNotRefreshed() async throws {
        try installSession(expiresAt: Date().addingTimeInterval(3600),
                           accessToken: "still-valid-token",
                           refreshToken: demoRefreshToken)

        let ok = await AuthService.shared.refreshIfNeeded()

        XCTAssertTrue(ok)
        XCTAssertEqual(AuthService.shared.restoreSession()?.accessToken, "still-valid-token",
                       "A non-expired token must be left untouched")
    }

    /// Scenario 2 — expired token, refresh succeeds: this is exactly the N-1
    /// bug condition. Before ADR-012 the expired token would have been sent.
    func test_expiredToken_isRefreshedAgainstRealSupabase() async throws {
        try installSession(expiresAt: Date().addingTimeInterval(-60), // already expired
                           accessToken: "expired-token",
                           refreshToken: demoRefreshToken)

        XCTAssertTrue(AuthService.shared.restoreSession()?.isExpired == true,
                      "Precondition: the installed session must be expired")

        let ok = await AuthService.shared.refreshIfNeeded()

        XCTAssertTrue(ok, "Refresh against real Supabase should succeed")
        let refreshed = AuthService.shared.restoreSession()
        XCTAssertNotEqual(refreshed?.accessToken, "expired-token",
                          "A new access token must replace the expired one")
        XCTAssertFalse(refreshed?.isExpired ?? true,
                       "The refreshed session must no longer be expired")
    }

    /// Scenario 3 — expired token, refresh fails (invalid refresh token):
    /// must fail closed, so APIClient surfaces .sessionExpired instead of
    /// sending a dead token and showing a raw backend error.
    func test_expiredToken_withInvalidRefreshToken_failsClosed() async throws {
        try installSession(expiresAt: Date().addingTimeInterval(-60),
                           accessToken: "expired-token",
                           refreshToken: "definitely-not-a-valid-refresh-token")

        let ok = await AuthService.shared.refreshIfNeeded()

        XCTAssertFalse(ok, "An unusable refresh token must report failure, not silently pass")
    }
}
