import UserNotifications

/// Local-only notifications — no APNs, no server push, no Apple Developer
/// Program entitlement needed. Real remote push (new events, social
/// activity) needs a paid Apple Developer account for the push
/// certificate/key and is out of scope until that's active.
@MainActor
final class NotificationService {
    static let shared = NotificationService()

    func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            #if DEBUG
            print("[Notifications] Permission error:", error)
            #endif
            return false
        }
    }

    func scheduleLocal(title: String, body: String, delay: TimeInterval = 1) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                           content: content,
                                           trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    /// Reminds the user ~15 min before a Skip the Line pass or event ticket
    /// expires. Best-effort: no-ops silently if permission is denied or
    /// there's less than 5 seconds of useful lead time left.
    func scheduleExpiryReminder(title: String, body: String, validUntil: Date) {
        Task {
            guard await requestPermission() else { return }
            let leadTime: TimeInterval = 15 * 60
            let delay = validUntil.timeIntervalSinceNow - leadTime
            guard delay > 5 else { return }
            scheduleLocal(title: title, body: body, delay: delay)
        }
    }

    /// Reminds the user ~30 min before a table reservation's time slot.
    func scheduleUpcomingReminder(title: String, body: String, at date: Date) {
        Task {
            guard await requestPermission() else { return }
            let leadTime: TimeInterval = 30 * 60
            let delay = date.timeIntervalSinceNow - leadTime
            guard delay > 5 else { return }
            scheduleLocal(title: title, body: body, delay: delay)
        }
    }
}
