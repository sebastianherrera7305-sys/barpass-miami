import Foundation

struct TicketPackage: Identifiable {
    let id       = UUID()
    let name:      String
    let price:     Double
    let perks:     [String]
    let badge:     String?
    let emoji:     String

    static let general = TicketPackage(
        name:  "General Admission",
        price: 20,
        perks: ["Entrada garantizada", "Sin hacer fila de cover", "Válido toda la noche"],
        badge: nil,
        emoji: "🎟️"
    )
    static let vip = TicketPackage(
        name:  "VIP Access",
        price: 45,
        perks: ["Entrada garantizada", "Acceso zona VIP", "1 drink de bienvenida", "Sin hacer fila"],
        badge: "MÁS POPULAR",
        emoji: "⭐️"
    )
    static let allAccess = TicketPackage(
        name:  "All Access",
        price: 80,
        perks: ["Todo lo de VIP", "Open bar 1 hora", "Zona privada con mesa", "Meet & greet artista"],
        badge: nil,
        emoji: "👑"
    )

    static let all: [TicketPackage] = [.general, .vip, .allAccess]
}

struct EventTicket: Identifiable {
    let id:          UUID
    let ticketCode:  String
    let eventName:   String
    let venueName:   String
    let venueId:     String
    let eventDate:   Date
    let quantity:    Int
    let package:     String
    let amount:      Double
    let payMethod:   String
    let purchasedAt: Date

    var formattedDate: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_MX")
        f.dateFormat = "EEEE d 'de' MMMM · h:mm a"
        return f.string(from: eventDate).capitalized
    }

    var expiresAt: Date { eventDate.addingTimeInterval(3600 * 4) }

    var isExpired: Bool { Date() > expiresAt }

    static func new(eventName: String, venueName: String, venueId: String,
                    eventDate: Date, quantity: Int, package: String,
                    amount: Double, payMethod: String) -> EventTicket {
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        let code  = String((0..<8).compactMap { _ in chars.randomElement() })
        return EventTicket(
            id:          UUID(),
            ticketCode:  code,
            eventName:   eventName,
            venueName:   venueName,
            venueId:     venueId,
            eventDate:   eventDate,
            quantity:    quantity,
            package:     package,
            amount:      amount,
            payMethod:   payMethod,
            purchasedAt: Date()
        )
    }
}
