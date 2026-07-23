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

enum MusicGenre: String, Codable, CaseIterable {
    case edm        = "EDM"
    case house      = "House"
    case latin      = "Latin"
    case hipHop     = "Hip-Hop"
    case reggaeton  = "Reggaeton"
    case pop        = "Pop"
    case live       = "Live Music"
    case jazz       = "Jazz"
    case techHouse  = "Tech House"
    case rnb        = "R&B"
}

// MARK: - Domain Models

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

    var priceRange: String {
        guard let cover = coverMen else { return "Sin cover" }
        return cover == 0 ? "Sin cover" : "$\(cover)+ cover"
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

// MARK: - Design system tokens live in Resources/DesignSystem.swift
