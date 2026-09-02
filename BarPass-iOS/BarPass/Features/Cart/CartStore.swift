import Foundation
import Combine

@MainActor
final class CartStore: ObservableObject {
    @Published var items:     [CartItem] = []
    @Published var venueName: String     = ""
    @Published var venueId:   String     = ""

    // Must mirror barpass-v2/src/app/api/transactions/route.ts's own formula
    // exactly (TAX_RATE = 0.07, same rounding) — that route recomputes the
    // charge from `items` server-side and ignores whatever total the client
    // shows, so a different formula here doesn't change what gets charged,
    // it just makes the app lie about it before the fact (TestFlight/audit:
    // cart showed subtotal + $0.99 while Stripe charged subtotal + 7% tax).
    private static let taxRate = 0.07
    var subtotal:   Double { items.reduce(0) { $0 + $1.price * Double($1.qty) } }
    var serviceFee: Double { ((subtotal * Self.taxRate) * 100).rounded() / 100 }
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
        BPAnalytics.track(.addToCart(item: name, venue: venueName))
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
