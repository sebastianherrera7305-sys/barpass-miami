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
    /// Real Ticketmaster static seatmap image for this venue (from a
    /// current event's `seatmap.staticUrl` — the seating geometry is the
    /// same venue-wide, so one event's image stands in for "the stadium's
    /// map"). Nil until synced.
    let seatmapURL: String?
    /// Real photo + description, sourced the same way venues are (Google
    /// Places) — never fabricated. Nil until backfilled; the detail view
    /// falls back to the psychedelic background art when absent instead
    /// of rendering nothing (TestFlight feedback: "doesn't show a picture
    /// or description of the stadium").
    let imageURL: String?
    let description: String?

    /// City derived from `address`, which has no column of its own in
    /// `stadiums`. US addresses here are consistently
    /// "street, City, ST ZIP", so the component before the state/ZIP is the
    /// city. Returns nil rather than a guess if the shape doesn't match —
    /// the list groups those under "Other" instead of inventing a city.
    var city: String? {
        let parts = address.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 3 else { return nil }
        let candidate = parts[parts.count - 2]
        return candidate.isEmpty ? nil : candidate
    }
}

enum StadiumPOIType: String, Codable, CaseIterable {
    case bar, concession, merch, restroom, firstAid = "first_aid"
    case guestServices = "guest_services", elevator, entrance, other

    var label: String {
        switch self {
        case .bar: return L10n.tSync("stadium.poi.bar")
        case .concession: return L10n.tSync("stadium.poi.concession")
        case .merch: return L10n.tSync("stadium.poi.merch")
        case .restroom: return L10n.tSync("stadium.poi.restroom")
        case .firstAid: return L10n.tSync("stadium.poi.firstAid")
        case .guestServices: return L10n.tSync("stadium.poi.guestServices")
        case .elevator: return L10n.tSync("stadium.poi.elevator")
        case .entrance: return L10n.tSync("stadium.poi.entrance")
        case .other: return L10n.tSync("stadium.poi.other")
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

    /// There's no per-POI description in the data yet (stadium_pois has no
    /// such column) — falling back to type + level keeps every card
    /// showing *something* instead of just a bare name, which read as
    /// "broken" to testers (TestFlight feedback: "Bars/cards without
    /// info"). Real per-POI descriptions can replace this once sourced.
    var subtitle: String {
        sectionOrConcourse ?? "\(type.label) · \(levelName)"
    }
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
