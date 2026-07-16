import Foundation

struct TablePackage: Identifiable, Equatable {
    let id:          String
    let name:        String
    let emoji:       String
    let guestRange:  String
    let minSpend:    Double
    let deposit:     Double
    let perks:       [String]

    // perks are l10n keys resolved at the view via L10n.shared.t(...).
    static let all: [TablePackage] = [
        TablePackage(id: "standard", name: "Standard VIP",  emoji: "🥂",
                     guestRange: "2–4 personas", minSpend: 500,  deposit: 100,
                     perks: ["table.perk.standard.0", "table.perk.standard.1", "table.perk.standard.2"]),
        TablePackage(id: "premium",  name: "Premium",       emoji: "🍾",
                     guestRange: "4–6 personas", minSpend: 1000, deposit: 200,
                     perks: ["table.perk.premium.0", "table.perk.premium.1", "table.perk.premium.2", "table.perk.premium.3"]),
        TablePackage(id: "ultra",    name: "Ultra VIP",     emoji: "👑",
                     guestRange: "6–10 personas", minSpend: 2500, deposit: 500,
                     perks: ["table.perk.ultra.0", "table.perk.ultra.1", "table.perk.ultra.2", "table.perk.ultra.3"]),
    ]
}

struct TableReservation: Identifiable, Codable, Equatable {
    let id:           UUID
    let confirmCode:  String
    let venueId:      String
    let venueName:    String
    let packageId:    String
    let packageName:  String
    let guestCount:   Int
    let timeSlot:     String
    let date:         Date
    let deposit:      Double
    let minSpend:     Double
    let payMethod:    String
    let createdAt:    Date

    var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM · HH:mm"
        f.locale = Locale(identifier: "es_MX")
        return f.string(from: date).capitalized
    }

    static func new(venueId: String, venueName: String,
                    package pkg: TablePackage, guestCount: Int,
                    timeSlot: String, slotDate: Date,
                    payMethod: String) -> TableReservation {
        TableReservation(
            id:          UUID(),
            confirmCode: "\(venueId.prefix(3).uppercased())-VIP-\(String(UUID().uuidString.prefix(6).uppercased()))",
            venueId:     venueId,
            venueName:   venueName,
            packageId:   pkg.id,
            packageName: pkg.name,
            guestCount:  guestCount,
            timeSlot:    timeSlot,
            date:        slotDate,
            deposit:     pkg.deposit,
            minSpend:    pkg.minSpend,
            payMethod:   payMethod,
            createdAt:   Date()
        )
    }
}
