import SwiftUI
import UserNotifications
import BackgroundTasks
@preconcurrency import Stripe

@main
struct BarPassApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var cart     = CartStore()
    @ObservedObject private var appearanceStore = AppearanceStore.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        ImageCache.configure()
        StripeAPI.defaultPublishableKey = StripeConfig.publishableKey
        // Everything done inside a venue (check-in, the photo, the age and
        // price reports) is queued locally when the network can't carry it.
        // The queue holds no repositories of its own, so the app has to tell
        // it how to perform each kind — and it must happen before any view
        // can enqueue, hence init and not a .task.
        OfflineQueue.shared.installPerformHandlers()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(cart)
                .preferredColorScheme(appearanceStore.appearance == .dark ? .dark : .light)
                // SwiftUI's own hook for incoming URLs (custom scheme + universal
                // links), alongside AppDelegate.application(open:). Belt-and-
                // suspenders, and in practice the one that actually fires: with
                // this app's WindowGroup-only Scene (no explicit UIScene
                // manifest), the UIKit AppDelegate path never invoked
                // application(open:) in testing — every delivery came through
                // here. Kept both since they're independent and idempotent (both
                // just parse the same URL into the same route), but .onOpenURL
                // is the one this app can actually rely on.
                .onOpenURL { url in
                    guard let route = DeepLinkRouter.parse(url) else { return }
                    appState.deepLinkURL = url
                    appState.pendingRoute = route
                }
                // Launch and every return to the foreground: the walk out of
                // the club is usually where the signal comes back, and the
                // app is in the user's hand at that exact moment. The queue's
                // own NWPathMonitor covers reconnects while the app is open;
                // this covers the far more common "phone was in a pocket".
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await OfflineQueue.shared.flush() }
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    private static let cacheTaskID = "io.barpass.cache.refresh"

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        registerBackgroundTask()
        PassRegistrationOutbox.shared.start()
        return true
    }

    private func registerBackgroundTask() {
        // `using: .main`, not nil. Every TestFlight crash on record (builds 22,
        // 26 and 50 — 2026-09-03, 09-04, 09-06) was this exact spot: with a nil
        // queue, BGTaskScheduler ran the handler on a background dispatch
        // queue; the closure calls into this @MainActor delegate, so Swift 6's
        // runtime isolation check trapped (SIGTRAP in
        // _dispatch_assert_queue_fail ← swift_task_checkIsolated ← closure #1
        // in registerBackgroundTask). It fired whenever iOS woke the app in the
        // background for the hourly refresh ("Role: Non UI", 0.15s after
        // launch), so the user saw "the app crashed" on the next open without
        // ever having touched it. Running the handler on the main queue makes
        // the isolation check pass; the work itself is trivial (reschedule +
        // complete), so main is also the right queue for it.
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.cacheTaskID, using: .main) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            MainActor.assumeIsolated {
                self.handleCacheRefresh(task: refreshTask)
            }
        }
        scheduleNextCacheRefresh()
    }

    private func scheduleNextCacheRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.cacheTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handleCacheRefresh(task: BGAppRefreshTask) {
        scheduleNextCacheRefresh()
        task.setTaskCompleted(success: true)
    }

    // MARK: - Push notifications

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        NotificationCenter.default.post(name: .deviceTokenReceived, object: token)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        #if DEBUG
        print("[BarPass] Push registration failed:", error)
        #endif
    }

    // MARK: - Deep links

    private static let allowedCustomPaths: Set<String> = [
        "/spotify-callback"
    ]

    private static let allowedUniversalHosts: Set<String> = [
        "\(SupabaseConfig.projectRef).supabase.co",
        "barpass-v2.vercel.app",
        "sebastianherrera7305-sys.github.io"
    ]

    private func isValidDeepLink(_ url: URL) -> Bool {
        if url.scheme == "barpass" {
            // allowedCustomPaths covers exact-match, non-routable paths (e.g. the
            // Spotify OAuth callback). Everything else goes through
            // DeepLinkRouter.parse — the same parser AppState uses to build a
            // navigable route — so a link is accepted here if and only if
            // something can actually act on it downstream. Before this, any
            // barpass://trip/{id} or barpass://venue/{id} was silently rejected
            // right here, before ever reaching AppState/DeepLinkRouter: the
            // static allowlist only ever contained "/spotify-callback".
            return Self.allowedCustomPaths.contains(url.path) || DeepLinkRouter.parse(url) != nil
        }
        if url.scheme == "https" || url.scheme == "http" {
            guard let host = url.host else { return false }
            return Self.allowedUniversalHosts.contains(host)
        }
        return false
    }

    func application(_ app: UIApplication, open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        guard isValidDeepLink(url) else {
            #if DEBUG
            print("[BarPass] Rejected deep link: \(url.absoluteString)")
            #endif
            return false
        }
        NotificationCenter.default.post(name: .deepLinkReceived, object: url)
        return true
    }

    // Universal links
    func application(_ application: UIApplication,
                     continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        if userActivity.activityType == NSUserActivityTypeBrowsingWeb,
           let url = userActivity.webpageURL {
            guard isValidDeepLink(url) else {
                #if DEBUG
                print("[BarPass] Rejected universal link: \(url.absoluteString)")
                #endif
                return false
            }
            NotificationCenter.default.post(name: .deepLinkReceived, object: url)
            return true
        }
        return false
    }
}

extension AppDelegate: @preconcurrency UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    // Tap on a push notification while app is in background
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        if let deepLink = userInfo["deep_link"] as? String,
           let url = URL(string: deepLink),
           isValidDeepLink(url) {
            NotificationCenter.default.post(name: .deepLinkReceived, object: url)
        }
        completionHandler()
    }
}

extension Notification.Name {
    static let deviceTokenReceived = Notification.Name("deviceTokenReceived")
    static let deepLinkReceived    = Notification.Name("deepLinkReceived")
    static let selectedCityChanged = Notification.Name("selectedCityChanged")
    /// Posted by SupabaseVenueRepository (object: [BarPassVenue]) when a
    /// background catalog refresh lands after a cache-first launch.
    static let venueCatalogRefreshed = Notification.Name("venueCatalogRefreshed")
}
