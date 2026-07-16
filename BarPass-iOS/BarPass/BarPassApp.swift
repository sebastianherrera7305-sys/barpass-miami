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

    init() {
        ImageCache.configure()
        StripeAPI.defaultPublishableKey = StripeConfig.publishableKey
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(cart)
                .preferredColorScheme(appearanceStore.appearance == .dark ? .dark : .light)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    private static let cacheTaskID = "io.barpass.cache.refresh"

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        registerBackgroundTask()
        return true
    }

    private func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.cacheTaskID, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            self.handleCacheRefresh(task: refreshTask)
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
            return Self.allowedCustomPaths.contains(url.path)
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
}
