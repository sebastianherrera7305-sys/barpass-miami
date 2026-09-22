import Foundation

/// What a safety push says, parsed from `userInfo`. Pure and `Sendable`, so
/// the rules that decide what a notification may open are testable without a
/// device (BarPassTests/SafetyGroupTests.swift).
///
/// The wire shape is `barpass-v2/src/lib/safety-push-rules.ts`:
///   seek_leader   → { alert_type, seek_id, group_id, expires_at }   (alert, leader only)
///   group_refresh → { alert_type, group_id }                        (silent, content-available)
///
/// Ningún payload lleva posición, distancia ni dirección.
struct SafetyPushPayload: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Alguien del grupo busca al líder. Abre el RADAR — no el punto de encuentro.
        case seekLeader(seekId: String, expiresAt: Date?)
        case groupRefresh
    }

    let kind: Kind
    let groupId: String?

    /// nil = not a safety push at all (a deep-link push, a pass reminder...).
    /// Malformed safety pushes are also nil rather than half-parsed: a seek
    /// with no valid seek id cannot be verified, so it cannot open anything.
    static func parse(_ userInfo: [AnyHashable: Any]) -> SafetyPushPayload? {
        guard let type = userInfo["alert_type"] as? String else { return nil }
        let groupId = (userInfo["group_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }

        switch type {
        case "seek_leader":
            guard let seekId = userInfo["seek_id"] as? String, UUID(uuidString: seekId) != nil else { return nil }
            let expires = (userInfo["expires_at"] as? String).flatMap(Self.parseDate)
            return SafetyPushPayload(kind: .seekLeader(seekId: seekId, expiresAt: expires), groupId: groupId)
        case "group_refresh":
            return SafetyPushPayload(kind: .groupRefresh, groupId: groupId)
        default:
            return nil
        }
    }

    /// A seek from 20 minutes ago whose notification is tapped tonight from
    /// the notification centre must not open a radar. `nil` expiry (a payload
    /// without one) is treated as unknown, not as "never expires": the server
    /// check is then the only gate.
    static func isStale(expiresAt: Date?, now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= now
    }

    private static func parseDate(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }
}

/// Which APNs environment THIS build's token belongs to. A Debug build run
/// from Xcode registers with the sandbox gateway; TestFlight and App Store
/// builds with production. Sending to the wrong one is a 400 BadDeviceToken.
enum PushEnvironment {
    static var current: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }
}

/// Hex form of an APNs device token, exactly what `AppDelegate` already
/// posts on `.deviceTokenReceived`.
enum DeviceTokenFormat {
    static func hex(_ data: Data) -> String { data.map { String(format: "%02.2hhx", $0) }.joined() }

    /// The server's CHECK is 32-200 chars; a token outside that is a bug in
    /// the caller, not something to upload and get a 400 for.
    static func isPlausible(_ token: String) -> Bool { (32...200).contains(token.count) }
}
