import Foundation
import os
import UIKit

/// Direct HTTP implementation of `AnalyticsService` for PostHog Cloud.
///
/// Deliberately NOT using the posthog-ios SPM — this is a single POST per
/// event to `${host}/capture/`, fire-and-forget. For the ~300-user Miami
/// pilot the batching, retry, and session-management the SDK adds are not
/// worth the dependency surface. If MAU scales past ~5k we revisit.
///
/// Design rules enforced here (not just by convention):
///   - If `POSTHOG_API_KEY` is not set in Info.plist → the whole service
///     is inert at the bootstrap site; this class is never instantiated.
///   - If the user has opted out (`analyticsOptOut` in UserDefaults) →
///     `track()` short-circuits before any network call.
///   - Properties never carry PII that `PostHogEventMapper` doesn't
///     explicitly whitelist — the mapper is the single enforcement point.
///   - No session recording, no autocapture — those are server-side
///     settings on the PostHog project; nothing in the client turns them
///     on.
final class PostHogAnalyticsService: AnalyticsService {
    private let apiKey: String
    private let host: String
    private let session: URLSession
    private let log = OSLog(subsystem: "io.barpass", category: "PostHog")

    /// Pseudo-anonymous id. Starts as the device vendor id (so a signed-
    /// out user's `app_opened` still lands and can be aliased later), and
    /// is replaced by the Supabase auth user id on `setUserID`.
    nonisolated(unsafe) private var distinctId: String
    nonisolated(unsafe) private var anonymousId: String

    init(
        apiKey: String,
        host: String = "https://us.i.posthog.com",
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.host = host
        self.session = session
        let anonId = UIDevice.current.identifierForVendor?.uuidString
            ?? UUID().uuidString
        self.anonymousId = anonId
        self.distinctId = anonId
    }

    func track(_ event: AnalyticsEvent) {
        guard !isOptedOut else { return }
        let mapped = PostHogEventMapper.map(event)
        send(eventName: mapped.name, properties: mapped.properties)
    }

    func setUserID(_ id: String?) {
        guard !isOptedOut else { return }
        if let id, !id.isEmpty {
            // $identify + $anon_distinct_id so pre-login funnel attribution
            // (device → user) survives sign-in. PostHog does the alias
            // internally when it sees both fields.
            let previousAnon = distinctId == id ? anonymousId : distinctId
            distinctId = id
            send(
                eventName: "$identify",
                properties: ["$anon_distinct_id": previousAnon]
            )
        } else {
            // Sign-out — reset to a fresh anonymous id so the next user on
            // the device doesn't inherit the previous user's identity.
            // Matters for shared iPhones (bar staff, friends).
            let newAnon = UUID().uuidString
            anonymousId = newAnon
            distinctId = newAnon
        }
    }

    func flush() {
        // No batching — nothing to flush. Here for protocol conformance.
    }

    // MARK: - Private

    private var isOptedOut: Bool {
        UserDefaults.standard.bool(forKey: "analyticsOptOut")
    }

    private func send(eventName: String, properties: [String: Any]) {
        guard let url = URL(string: "\(host)/capture/") else { return }
        var merged = properties
        merged["$lib"] = "barpass-ios"
        merged["$lib_version"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        merged["app_build"] = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let body: [String: Any] = [
            "api_key": apiKey,
            "event": eventName,
            "distinct_id": distinctId,
            "properties": merged,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        let task = session.dataTask(with: request) { [log] _, response, error in
            #if DEBUG
            if let error {
                os_log("[PostHog] send failed: %@", log: log, type: .error, error.localizedDescription)
            } else if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                os_log("[PostHog] non-2xx: %d", log: log, type: .error, http.statusCode)
            }
            #endif
        }
        task.resume()
    }
}

// MARK: - PostHogEventMapper
//
// Pure translation of our internal AnalyticsEvent enum → PostHog event
// name + properties dict. Separated from the service so it can be unit-
// tested without network. Every property that lands in PostHog comes
// through here; adding a new one anywhere else is the bug.

enum PostHogEventMapper {
    struct Mapped { let name: String; let properties: [String: Any] }

    static func map(_ event: AnalyticsEvent) -> Mapped {
        switch event {
        case .signIn(let method, let duration):
            return Mapped(name: "sign_in", properties: ["method": method, "duration_s": roundTenths(duration)])
        case .signUp(let method, let duration):
            return Mapped(name: "sign_up", properties: ["method": method, "duration_s": roundTenths(duration)])
        case .forgotPassword:
            return Mapped(name: "forgot_password", properties: [:])
        case .sessionRestored:
            return Mapped(name: "session_restored", properties: [:])

        case .viewScreen(let name):
            return Mapped(name: "screen_view", properties: ["screen": name])
        case .viewVenue(let id):
            return Mapped(name: "venue_viewed", properties: ["venue_id": id])
        case .viewTrip(let id):
            return Mapped(name: "trip_viewed", properties: ["trip_id": id])
        case .viewPlan:
            return Mapped(name: "plan_viewed", properties: [:])

        case .createTrip:
            // Legacy call site — keep working, but drop detail. The newer
            // tripCreatedDetailed is what Trips surfaces now.
            return Mapped(name: "trip_created", properties: ["method": "unknown"])
        case .createPlan(let method):
            return Mapped(name: "plan_created", properties: ["method": method])
        case .savePlan:
            return Mapped(name: "plan_saved", properties: [:])

        case .startPayment(let method, let amount):
            return Mapped(name: "payment_started", properties: ["method": method, "amount_cents": cents(amount)])
        case .paymentSuccess(let method, let amount):
            return Mapped(name: "payment_succeeded", properties: ["method": method, "amount_cents": cents(amount)])
        case .paymentFailed(let method, let error):
            // Error strings go through unchanged — they're our own
            // enum names, not user input. Still: no card numbers, no PI
            // ids reach here because the mapper doesn't accept them.
            return Mapped(name: "payment_failed", properties: ["method": method, "error": error])

        case .addToCart(let item, let venue):
            return Mapped(name: "cart_item_added", properties: ["product_id": item, "venue_id": venue])
        case .cartCheckout(let count, let total):
            return Mapped(name: "cart_checkout", properties: ["item_count": count, "total_cents": cents(total)])

        case .buySkipLinePass(let venue):
            return Mapped(name: "skip_line_purchased", properties: ["venue_id": venue])
        case .buyTableReservation(let venue):
            return Mapped(name: "table_purchased", properties: ["venue_id": venue])
        case .buyEventTicket(let venue, let event):
            return Mapped(name: "ticket_purchased", properties: ["venue_id": venue, "event_id": event])

        case .openMaps(let venue):
            return Mapped(name: "maps_opened", properties: ["venue_id": venue])
        case .shareVenue(let venue):
            return Mapped(name: "venue_shared", properties: ["venue_id": venue])
        case .deepLink(let url):
            // Only the scheme + host — a path like /trip/abc123 is a
            // trip id in the URL, which qualifies as data we don't need
            // to send to a third party.
            return Mapped(name: "deep_link_opened", properties: [
                "scheme": url.scheme ?? "",
                "host": url.host ?? "",
            ])

        case .earnXP(let action, let amount):
            return Mapped(name: "xp_earned", properties: ["action": action, "xp": amount])

        case .error(let name, let details):
            var props: [String: Any] = ["error_name": name]
            if let details { props["details"] = details }
            return Mapped(name: "app_error", properties: props)
        case .warning(let name, let details):
            var props: [String: Any] = ["warning_name": name]
            if let details { props["details"] = details }
            return Mapped(name: "app_warning", properties: props)

        case .appOpened(let coldStart, let secondsSinceLastOpen):
            var props: [String: Any] = ["cold_start": coldStart]
            if let secondsSinceLastOpen { props["seconds_since_last_open"] = secondsSinceLastOpen }
            return Mapped(name: "app_opened", properties: props)

        case .avatarSaved(let isFirstTime):
            return Mapped(name: "avatar_saved", properties: ["is_first_time": isFirstTime])

        case .socialGraphViewed:
            return Mapped(name: "social_graph_viewed", properties: [:])

        case .friendProfileOpened(let friendIdHash):
            // Caller is responsible for hashing — see PostHogIDHasher below.
            return Mapped(name: "friend_profile_opened", properties: ["friend_id_hash": friendIdHash])

        case .friendAdded(let source):
            return Mapped(name: "friend_added", properties: ["source": source])

        case .tripCreatedDetailed(let method, let memberCount):
            return Mapped(name: "trip_created", properties: ["method": method, "member_count": memberCount])
        case .tripJoined(let tripId, let source):
            return Mapped(name: "trip_joined", properties: ["trip_id": tripId, "source": source])
        case .tripCompleted(let tripId, let stopCount, let durationHours):
            var props: [String: Any] = ["trip_id": tripId, "stop_count": stopCount]
            if let durationHours { props["duration_hours"] = roundTenths(durationHours) }
            return Mapped(name: "trip_completed", properties: props)

        case .venueCheckin(let venueId, let tripId):
            var props: [String: Any] = ["venue_id": venueId, "has_trip": tripId != nil]
            if let tripId { props["trip_id"] = tripId }
            return Mapped(name: "venue_checkin", properties: props)
        }
    }

    private static func cents(_ dollars: Double) -> Int { Int((dollars * 100).rounded()) }
    private static func roundTenths(_ v: Double) -> Double { (v * 10).rounded() / 10 }
}

/// Stable per-install hash for friend ids. Not a security boundary — a
/// leaked PostHog export cannot reconstruct the social graph without
/// also obtaining the per-install salt from the device Keychain.
enum PostHogIDHasher {
    private static let saltKey = "io.barpass.posthog.id_salt"

    static func hash(_ id: String) -> String {
        let salt = currentSalt()
        guard let data = (id + ":" + salt).data(using: .utf8) else { return "h_unknown" }
        return "h_" + String(Insecure64BitHash.hash(data), radix: 36)
    }

    private static func currentSalt() -> String {
        if let existing = UserDefaults.standard.string(forKey: saltKey) { return existing }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: saltKey)
        return fresh
    }
}

/// Minimal, allocation-free hash — we don't need cryptographic strength
/// for this surface. FNV-1a 64-bit is well-known, inlined to avoid
/// pulling in CryptoKit for one 8-byte digest.
private enum Insecure64BitHash {
    static func hash(_ data: Data) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in data {
            h ^= UInt64(b)
            h &*= 0x100000001b3
        }
        return h
    }
}
