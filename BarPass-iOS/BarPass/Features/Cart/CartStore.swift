import Foundation
import Combine

@MainActor
final class CartStore: ObservableObject {
    @Published var items:     [CartItem] = []
    @Published var venueName: String     = ""
    @Published var venueId:   String     = ""

    var subtotal:   Double { items.reduce(0) { $0 + $1.price * Double($1.qty) } }
    var serviceFee: Double { items.isEmpty ? 0 : 0.99 }
    var total:      Double { ((subtotal + serviceFee) * 100).rounded() / 100 }
    var itemCount:  Int    { items.reduce(0) { $0 + $1.qty } }
    var isEmpty:    Bool   { items.isEmpty }

    func add(name: String, price: Double, emoji: String,
             venueId: String = "", venueName: String = "") {
        self.venueId   = venueId
        self.venueName = venueName
        if let idx = items.firstIndex(where: { $0.name == name }) {
            items[idx].qty += 1
        } else {
            items.append(CartItem(name: name, price: price, emoji: emoji,
                                  venueId: venueId, venueName: venueName))
        }
    }

    func changeQty(id: UUID, delta: Int) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].qty += delta
        if items[idx].qty <= 0 { items.remove(at: idx) }
    }

    func clear() {
        items     = []
        venueName = ""
        venueId   = ""
    }
}
