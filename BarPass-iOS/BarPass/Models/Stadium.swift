import Foundation

/// Real, sourced venue-map data — never invented. Every POI traces back to
/// `sourceURL`; `confidence` stays "unverified" when research couldn't
/// confirm it against the official source (see stadiums.sql).
struct Stadium: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let address: String
    let lat: Double?
    let lng: Double?
    let sourceURL: String
}

enum StadiumPOIType: String, Codable, CaseIterable {
    case bar, concession, merch, restroom, firstAid = "first_aid"
    case guestServices = "guest_services", elevator, entrance, other

    var label: String {
        switch self {
        case .bar: return "Bares"
        case .concession: return "Comida"
        case .merch: return "Tienda"
        case .restroom: return "Baños"
        case .firstAid: return "Primeros auxilios"
        case .guestServices: return "Servicios"
        case .elevator: return "Ascensores"
        case .entrance: return "Entradas"
        case .other: return "Otros"
        }
    }

    var icon: String {
        switch self {
        case .bar: return "wineglass.fill"
        case .concession: return "fork.knife"
        case .merch: return "bag.fill"
        case .restroom: return "figure.dress.line.vertical.figure"
        case .firstAid: return "cross.case.fill"
        case .guestServices: return "person.fill.questionmark"
        case .elevator: return "arrow.up.arrow.down.square.fill"
        case .entrance: return "door.left.hand.open"
        case .other: return "star.fill"
        }
    }
}

struct StadiumPOI: Identifiable, Codable, Hashable {
    let id: String
    let stadiumId: String
    let levelName: String
    let levelOrder: Int
    let name: String
    let type: StadiumPOIType
    let sectionOrConcourse: String?
    let sourceURL: String
    let confidence: String
}

/// Real events from Ticketmaster Discovery API (sync-stadium-events.ts) —
/// never invented. `ticketURL` links to the real Ticketmaster listing.
struct StadiumEvent: Identifiable, Codable, Hashable {
    let id: String
    let stadiumId: String
    let name: String
    let startsAt: Date
    let ticketURL: String?
    let imageURL: String?
}
