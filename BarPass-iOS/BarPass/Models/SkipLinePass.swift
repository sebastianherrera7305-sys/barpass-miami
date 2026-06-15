import Foundation

struct SkipLinePass: Identifiable, Codable, Equatable {
    let id:          UUID
    let passCode:    String   // encoded in the QR
    let venueId:     String
    let venueName:   String
    let quantity:    Int
    let amount:      Double
    let purchasedAt: Date
    let validUntil:  Date
    let payMethod:   String

    var isValid: Bool { Date() < validUntil }

    var timeRemaining: String {
        let secs = Int(validUntil.timeIntervalSinceNow)
        guard secs > 0 else { return "Expirado" }
        let h = secs / 3600
        let m = (secs % 3600) / 60
        let s = secs % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    static func new(venueId: String, venueName: String,
                    quantity: Int, amount: Double, payMethod: String) -> SkipLinePass {
        let now = Date()
        return SkipLinePass(
            id:          UUID(),
            passCode:    "\(venueId)-\(UUID().uuidString.prefix(8).uppercased())",
            venueId:     venueId,
            venueName:   venueName,
            quantity:    quantity,
            amount:      amount,
            purchasedAt: now,
            validUntil:  now.addingTimeInterval(3 * 3600),
            payMethod:   payMethod
        )
    }
}
