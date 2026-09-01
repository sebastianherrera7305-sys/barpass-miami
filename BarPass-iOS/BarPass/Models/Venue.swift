import MapKit

// MARK: - Domain Enums

enum VenueType: String, Codable, CaseIterable {
    case club       = "Club"
    case rooftop    = "Rooftop"
    case bar        = "Bar"
    case lounge     = "Lounge"
    case sportsBar  = "Sports Bar"
    case restaurant = "Restaurant"
    case brewery    = "Brewery"
}

/// One age bracket a venue fits, and where that claim comes from.
struct VenueAgeBracket: Codable, Hashable, Sendable {
    enum Source: String, Codable, Sendable {
        /// Desk research. An informed estimate, not an observation.
        case research
        /// 3+ real check-out reports for this bracket — see
        /// barpass-v2/supabase/venue_age_reports.sql.
        case userReports
    }

    /// "18_25", "25_35", "35_50".
    let id: String
    let source: Source
    /// Only set for `.userReports`.
    let reportCount: Int?

    /// "18–25" — an en dash, not a hyphen, and never the raw "18_25".
    var label: String { id.replacingOccurrences(of: "_", with: "–") }
}

/// The controlled vocabulary for what a venue actually plays.
///
/// `live` is a performance FORMAT, not a genre, and composes with one: a
/// honky-tonk booking country bands is `[.country, .live]`. It stays in this
/// list because it is the single most common thing a venue publishes about
/// itself, and because a venue that only advertises "live music" without ever
/// naming a style is a real and frequent case — `[.live]` alone is the honest
/// answer there.
///
/// The list grew from 10 to 14 to 22 to 25 as manual research kept hitting music the
/// vocabulary could not express. Each addition below was made only after a
/// documented venue was being tagged WRONG or LOSSILY without it — never
/// speculatively:
///   techno     Bauhaus Vegas states "house, techno, and tech-house"; folding
///              techno into house erased the distinction its own site draws.
///   disco      Ciao Ciao Disco, Jolene Sound Room, Arbella's "House, Soul,
///              Disco, Afro" — three venues where disco is the billing.
///   soul/funk  The pair appears together constantly ("funk and soul music
///              blasts through the speakers"). Folding soul into rnb made a
///              1970s vinyl bar look like a contemporary R&B room.
///   americana  MRB and Acme book roots/singer-songwriter acts. Folding it
///              into country was the closest wrong answer, not a right one.
///   reggae     Turned up three separate times (Bembe, Bar Room, Cuban
///              Creations) before it was added.
///   salsa      Dedicated salsa nights are a distinct thing a user searches
///              for — RedBar's "OYE CHICA", Caña's "Salsa Flow Tuesdays".
///   bachata    Same, and it is not interchangeable with salsa on the floor.
///
///   goth       Three venues program it as their whole identity — Elysium in
///              Austin (25 years), Chicago's Late Bar, and Bar Sinister at
///              Boardner's in LA. Calling them `rock` described almost nothing
///              about what happens there. Covers industrial, darkwave, EBM and
///              new wave.
///   dancehall  Was folding into `reggae`, which is the wrong room: Madame X
///              and Deluxx Fluxx in New York and Kultur in LA all bill
///              dancehall (and bashment) as a distinct night.
///   tejano     OK Corral books conjunto and tejano — tributes to Valerio
///              Longoria and Steve Jordan — and Mala Vida is regional
///              mexicano. Both collapsed into `latin`, which filed a tejano
///              dance hall and a reggaeton club under one label.
///
/// Still unrepresented and seen at least once: soca, freestyle, amapiano,
/// traditional Irish, vallenato, merengue, cumbia, zydeco, brass band. Those
/// fold into a parent term for now. Add them the same way — when a venue is
/// being mislabelled without them, not before. One sighting is a note; three
/// is a term.
enum MusicGenre: String, Codable, CaseIterable {
    case edm        = "EDM"
    case house      = "House"
    case techHouse  = "Tech House"
    case techno     = "Techno"
    case disco      = "Disco"
    case latin      = "Latin"
    case salsa      = "Salsa"
    case bachata    = "Bachata"
    case reggaeton  = "Reggaeton"
    case hipHop     = "Hip-Hop"
    case rnb        = "R&B"
    case soul       = "Soul"
    case funk       = "Funk"
    case pop        = "Pop"
    case live       = "Live Music"
    case jazz       = "Jazz"
    case blues      = "Blues"
    case country    = "Country"
    case americana  = "Americana"
    case rock       = "Rock"
    case goth       = "Goth"
    case reggae     = "Reggae"
    case dancehall  = "Dancehall"
    case afrobeats  = "Afrobeats"
    case tejano     = "Tejano"
}

// MARK: - Domain Models

/// Real 1-4 scale from Supabase `price_tier` (Google Places price level).
/// `.unknown` is the explicit normalization target for any value outside
/// 1...4 (missing, 0, negative, or a future out-of-range value) — chosen
/// once at the Supabase mapping boundary, never re-clamped in the UI.
/// Pure data: no display text lives here — see `PriceTier.symbol` in
/// DesignSystem.swift for how the UI layer renders it.
enum PriceTier: Int, Codable, CaseIterable, Sendable {
    case unknown = 0
    case tier1 = 1
    case tier2 = 2
    case tier3 = 3
    case tier4 = 4

    init(rawSupabaseValue: Int?) {
        guard let rawSupabaseValue, let tier = PriceTier(rawValue: rawSupabaseValue) else {
            self = .unknown
            return
        }
        self = tier
    }
}

struct PopularDrink: Identifiable, Codable {
    let id: String
    let name: String
    let price: Double
    let emoji: String
}

/// Real amenity/accessibility data from Google Places API v1. Every field is
/// an optional Bool — nil means "Google hasn't told us", never "false". The
/// UI must treat nil as "don't show this badge", not as a negative claim.
/// Only the amenities Google actually exposes are modeled here; things like
/// noise level, LGBTQ+-friendliness, and language support have no reliable
/// source and are deliberately NOT included (see venue_amenities_schema.sql).
struct VenueAmenities: Codable, Hashable {
    var wheelchairAccessible: Bool? = nil
    var outdoorSeating:       Bool? = nil
    var goodForGroups:        Bool? = nil
    var goodForWatchingSports: Bool? = nil
    var hasLiveMusic:         Bool? = nil
    var reservable:           Bool? = nil
    var servesVegetarianFood: Bool? = nil
    var restroom:             Bool? = nil

    var isEmpty: Bool {
        wheelchairAccessible == nil && outdoorSeating == nil && goodForGroups == nil
            && goodForWatchingSports == nil && hasLiveMusic == nil && reservable == nil
            && servesVegetarianFood == nil && restroom == nil
    }
}

struct VenueEvent: Identifiable, Codable {
    let id: String
    let title: String
    let date: Date
    let coverPrice: Double?
    let description: String
    /// Real end time when the source actually knows it — nil (not an
    /// invented time) when it doesn't, in which case `VenueTimeStatus`
    /// falls back to its fixed-duration assumption.
    var endDate: Date? = nil
}

struct BarPassVenue: Identifiable, Codable {
    let id:               String
    let name:             String
    let neighborhood:     String
    let address:          String
    let latitude:         Double
    let longitude:        Double
    let type:             VenueType
    let vibes:            [String]
    let musicGenres:      [MusicGenre]
    let rating:           Double
    let reviewCount:      Int
    let coverMen:         Int?
    let coverWomen:       Int?
    /// `.unknown` for venues cached before this field existed, and the
    /// explicit normalization target for any DB value outside 1...4 — see
    /// `PriceTier.init(rawSupabaseValue:)`, used once at the mapping layer.
    var priceTier:        PriceTier = .unknown
    let openTime:         String
    let closeTime:        String
    let avgSpend:         String
    let dressCode:        String
    let parking:          String
    let crowdLevel:       Int
    let bestArrivalTime:  String
    let peakHours:        String
    let popularDrinks:    [PopularDrink]
    let upcomingEvents:   [VenueEvent]
    let tags:             [String]
    let emoji:            String
    let instagramHandle:  String?
    let isTrending:       Bool
    let hasHappyHour:     Bool
    let happyHourUntil:   String?
    let isOpenNow:        Bool
    let photoUrls:        [String]
    let editorial:        String?
    /// Datos reales de Google Places — nil cuando Google no los tiene para
    /// este venue (nunca se inventan).
    var phone:            String? = nil
    var website:          String? = nil
    /// The web venue page's real key (barpass-v2 `/venues/[slug]`), not `id`.
    /// Optional (decode-safe: nil for anything cached before this field
    /// existed) — ShareManager only builds a web link when this is present.
    var slug:             String? = nil
    var amenities:        VenueAmenities = VenueAmenities()
    /// Derived Experience Tags (Venue Intelligence Layer) — computed
    /// server-side from real amenity/category data, never invented client-
    /// side. Empty until `derive-experience-tags.ts` has run for a venue.
    var experienceTags:   [ExperienceTag] = []
    /// Which age brackets this venue fits, from the `venue_age_effective`
    /// view. Empty — never a guessed default — for venues nothing has tagged
    /// yet. Carries `source` because the two are not the same claim: research
    /// is an informed estimate, real check-out reports are what actually
    /// happened, and the app should not present them identically.
    var ageBrackets:       [VenueAgeBracket] = []

    /// Just the ids, for filtering. Keeps existing call sites simple.
    var ageBracketIds: [String] { ageBrackets.map(\.id) }
    /// Multi-city readiness (Venue Intelligence Roadmap Phase 2). Optional
    /// for decode-safety against any venue cached before these existed —
    /// nil, not "Miami", when a source genuinely doesn't say. The live
    /// Supabase-backed catalog is 100% Miami today; these fields describe
    /// where a venue actually is, they don't imply other cities are seeded.
    var city:             String? = nil
    var country:          String? = nil
    var timezoneId:       String? = nil

    /// Key de traducción — se resuelve en la vista (@MainActor), no acá.
    var crowdDescriptionKey: String {
        switch crowdLevel {
        case 0: return "venue.crowd.empty"
        case 1: return "venue.crowd.chill"
        case 2: return "venue.crowd.moderate"
        case 3: return "venue.crowd.lively"
        case 4: return "venue.crowd.packed"
        case 5: return "venue.crowd.max"
        default: return "venue.crowd.na"
        }
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Preview

extension BarPassVenue {
    static let preview = BarPassVenue(
        id: "liv-miami",
        name: "LIV Miami",
        neighborhood: "South Beach",
        address: "4441 Collins Ave, Miami Beach",
        latitude: 25.8171,
        longitude: -80.1229,
        type: .club,
        vibes: ["VIP", "Luxury", "Bottle Service", "Celebrity"],
        musicGenres: [.edm, .hipHop, .pop],
        rating: 3.3,
        reviewCount: 2050,
        coverMen: 40,
        coverWomen: 20,
        openTime: "11:00 PM",
        closeTime: "5:00 AM",
        avgSpend: "$150–400",
        dressCode: "Upscale — no sneakers, no shorts",
        parking: "Valet $30",
        crowdLevel: 4,
        bestArrivalTime: "11:30 PM – 12:30 AM",
        peakHours: "1:00 AM – 3:00 AM",
        popularDrinks: [
            PopularDrink(id: "1", name: "Grey Goose Bottle", price: 350, emoji: "🍾"),
            PopularDrink(id: "2", name: "Ace of Spades", price: 800, emoji: "🥂"),
        ],
        upcomingEvents: [],
        tags: ["EDM", "VIP", "Nightclub", "South Beach"],
        emoji: "🔥",
        instagramHandle: "livmiami",
        isTrending: true,
        hasHappyHour: false,
        happyHourUntil: nil,
        isOpenNow: true,
        photoUrls: [],
        editorial: "Trendy, opulent Fontainebleau Hotel club.",
        slug: "liv-miami"
    )
}

#if DEBUG
/// Fixtures for the SwiftUI canvas only — DEBUG-gated so they never ship.
/// `preview` above is deliberately NOT in here: `LocalVenueRepository` uses
/// it as the real offline fallback, so it is production code.
extension BarPassVenue {
    /// Every amenity Google can report, all true — the "many chips" extreme
    /// for the Good-to-know row.
    static var previewAllAmenities: BarPassVenue {
        var venue = Self.preview
        venue.amenities = VenueAmenities(
            wheelchairAccessible: true,
            outdoorSeating: true,
            goodForGroups: true,
            goodForWatchingSports: true,
            hasLiveMusic: true,
            reservable: true,
            servesVegetarianFood: true,
            restroom: true
        )
        venue.priceTier = .tier4
        return venue
    }

    /// Longest real-world-plausible name, to catch truncation and wrapping in
    /// the hero title. `name` is `let`, so this needs a full initializer
    /// rather than a copy-and-mutate.
    static var previewLongName: BarPassVenue {
        BarPassVenue(
            id: "long-name-fixture",
            name: "The Grand Rooftop Lounge & Cocktail Terrace at Brickell Bay",
            neighborhood: "Downtown / Brickell Financial District",
            address: "1234 Brickell Bay Drive, Miami, FL 33131",
            latitude: 25.7617,
            longitude: -80.1918,
            type: .rooftop,
            vibes: ["Rooftop", "Sunset", "Craft Cocktails", "Date Night"],
            musicGenres: [.house, .jazz],
            rating: 4.7,
            reviewCount: 1284,
            coverMen: nil,
            coverWomen: nil,
            openTime: "5:00 PM",
            closeTime: "2:00 AM",
            avgSpend: "$60–120",
            dressCode: "Smart casual — no beachwear after 8 PM",
            parking: "Valet $25",
            crowdLevel: 3,
            bestArrivalTime: "7:00 PM – 9:00 PM",
            peakHours: "9:00 PM – 12:00 AM",
            popularDrinks: [],
            upcomingEvents: [],
            tags: ["Rooftop", "Brickell"],
            emoji: "🌇",
            instagramHandle: nil,
            isTrending: false,
            hasHappyHour: true,
            happyHourUntil: "8:00 PM",
            isOpenNow: true,
            photoUrls: [],
            editorial: nil,
            slug: "grand-rooftop-lounge",
            amenities: VenueAmenities(outdoorSeating: true, goodForGroups: true, reservable: true)
        )
    }
}
#endif

// MARK: - Design system tokens live in Resources/DesignSystem.swift
