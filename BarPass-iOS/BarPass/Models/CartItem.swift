import Foundation

struct CartItem: Identifiable, Codable, Equatable {
    let id: UUID
    var name:      String
    var price:     Double
    var emoji:     String
    var qty:       Int
    var venueId:   String?
    var venueName: String?

    init(id: UUID = UUID(), name: String, price: Double,
         emoji: String, qty: Int = 1,
         venueId: String? = nil, venueName: String? = nil) {
        self.id        = id
        self.name      = name
        self.price     = price
        self.emoji     = emoji
        self.qty       = qty
        self.venueId   = venueId
        self.venueName = venueName
    }
}
