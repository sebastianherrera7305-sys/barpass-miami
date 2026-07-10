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

struct VenueEvent: Identifiable, Codable {
    let id: String
    let title: String
    let date: Date
    let coverPrice: Double?
    let description: String
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

    var crowdDescription: String {
        switch crowdLevel {
        case 0: return "Vacío"
        case 1: return "Tranquilo"
        case 2: return "Moderado"
        case 3: return "Animado"
        case 4: return "Lleno"
        case 5: return "A tope"
        default: return "N/A"
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
        editorial: "Trendy, opulent Fontainebleau Hotel club."
    )
}

// MARK: - Design system tokens live in Resources/DesignSystem.swift
