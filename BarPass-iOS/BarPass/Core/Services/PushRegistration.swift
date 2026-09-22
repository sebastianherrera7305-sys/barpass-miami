import Foundation
import UIKit
import UserNotifications

/// Gets this phone's APNs token to the server. Until this existed nothing in
/// the app called `registerForRemoteNotifications()`: `AppDelegate` posted
/// `.deviceTokenReceived` and nobody was listening, and there was no table
/// to put a token in (supabase/safety_groups.sql §1).
///
/// The permission prompt is deliberately NOT asked at launch. It is asked
/// the first time someone creates or joins a safety group — the moment the
/// reason for it is obvious ("so your group can reach you") and a "no" costs
/// them something they can see. A cold prompt at first open is the one most
/// people deny, and iOS shows it once.
@MainActor
final class PushRegistration {
    static let shared = PushRegistration()

    /// `nonisolated` porque `unregisterStoredToken` es nonisolated y lo lee
    /// desde afuera del main actor. Es una constante de texto: no hay estado
    /// mutable que proteger, así que aislarla no compraba nada y sólo
    /// impedía compilar.
    private nonisolated static let storedTokenKey = "bp_push_token"

    private var repository: SafetyGroupRepository { RepositoryDependencies.safetyGroup }
    private var observer: NSObjectProtocol?
    private var token: String?
    private var uploadedToken: String?
    private var isUploading = false

    private init() {
        token = UserDefaults.standard.string(forKey: Self.storedTokenKey)
    }

    /// Call once at launch. Installs the token listener, and — only if the
    /// person already said yes in a past session — re-registers, because iOS
    /// can rotate the token and expects the app to ask again every launch.
    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .deviceTokenReceived, object: nil, queue: .main
        ) { [weak self] note in
            guard let hex = note.object as? String else { return }
            // `queue: .main` guarantees this runs on the main thread.
            MainActor.assumeIsolated { self?.didReceive(token: hex) }
        }
        Task { [weak self] in
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            self?.registerWithApple()
        }
    }

    /// Asks for permission if it was never asked, and registers. Returns
    /// whether alerts can reach this phone; a `false` is not an error, it is
    /// something the UI should say plainly ("you won't be notified").
    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            registerWithApple()
            return true
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            if granted { registerWithApple() }
            return granted
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    /// Re-attempts the upload, e.g. after sign-in when a token arrived
    /// before there was a session to attach it to.
    func uploadIfPossible() async {
        guard let token, DeviceTokenFormat.isPlausible(token), token != uploadedToken, !isUploading else { return }
        isUploading = true
        defer { isUploading = false }
        do {
            try await repository.registerDeviceToken(token, environment: PushEnvironment.current)
            uploadedToken = token
        } catch {
            // Not fatal and not retried in a loop: the next launch, sign-in
            // or group action tries again. A group still works without push.
        }
    }

    /// Forget the upload marker on sign-out so the next account re-registers
    /// the same phone under its own user id.
    func didSignOut() { uploadedToken = nil }

    private func registerWithApple() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    private func didReceive(token hex: String) {
        guard DeviceTokenFormat.isPlausible(hex) else { return }
        token = hex
        UserDefaults.standard.set(hex, forKey: Self.storedTokenKey)
        Task { await uploadIfPossible() }
    }

    /// Tells the server to stop pushing THIS phone for THIS account. Called
    /// from `AuthService.signOut()` with the token captured before the
    /// session is erased — afterwards there is no session to authorize it
    /// with, and the previous user would keep receiving the next user's
    /// group alerts on a shared phone.
    nonisolated static func unregisterStoredToken(accessToken: String) async {
        guard let token = UserDefaults.standard.string(forKey: storedTokenKey) else { return }
        guard let body = try? JSONSerialization.data(withJSONObject: ["p_token": token]),
              let request = try? SupabaseRESTClient.request(
                "POST", path: "rpc/unregister_device_token", body: body,
                accessToken: accessToken, timeout: 8) else { return }
        _ = try? await URLSession.shared.data(for: request)
    }
}
