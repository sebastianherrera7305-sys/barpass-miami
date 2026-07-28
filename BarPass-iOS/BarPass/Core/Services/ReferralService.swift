import Foundation

/// Client side of the referral flow. Its only job is to carry a code across
/// the pre-auth → post-auth boundary and hand it to the server; it never
/// decides attribution, qualification, or rewards (all server-authoritative).
///
/// Flow: a `barpass://invite/{code}` deep link is captured pre-auth and held
/// in UserDefaults (survives the signup flow / app relaunch). Once a session
/// exists, the pending code is sent to `/api/referral/attribute` exactly once
/// and cleared. Reward (if the user later qualifies) happens entirely server-
/// side on first pass redemption.
@MainActor
final class ReferralService {
    static let shared = ReferralService()
    private init() {}

    private let pendingKey = "bp_pending_referral_code"
    private let defaults = UserDefaults.standard

    /// Records a referral code seen via deep link, before the user may have an
    /// account. No-op if one is already pending (first code wins, matching the
    /// server's one-per-referred rule) or if the app already has a session and
    /// this exact user shouldn't be self-attributing later — validation is the
    /// server's job; this only stores.
    func capturePendingCode(_ code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, defaults.string(forKey: pendingKey) == nil else { return }
        defaults.set(trimmed, forKey: pendingKey)
    }

    /// If a code is pending and a session exists, attribute it once and clear.
    /// Safe to call repeatedly (e.g. on every MainTabView appear) — the server
    /// is idempotent, and the local code is cleared on success so it isn't
    /// resent. A network failure leaves the code pending for the next attempt.
    func attributePendingIfNeeded() async {
        guard let code = defaults.string(forKey: pendingKey),
              let session = AuthService.shared.restoreSession() else { return }
        do {
            try await APIClient.attributeReferral(idToken: session.accessToken, code: code)
            defaults.removeObject(forKey: pendingKey)
        } catch {
            // Leave the code pending; the next appear retries. Terminal server
            // rejections (invalid_code/self_referral) also clear it so a bad
            // code doesn't retry forever.
            if case APIClient.APIClientError.server(let reason) = error,
               reason == "invalid_code" || reason == "self_referral" {
                defaults.removeObject(forKey: pendingKey)
            }
        }
    }
}
