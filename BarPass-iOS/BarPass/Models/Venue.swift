import Foundation

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

struct Venue: Identifiable, Codable {
    let id:               String
    let name:             String
    let neighborhood:     String
    let address:          String
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
    let crowdLevel:       Int        // 0–5
    let bestArrivalTime:  String
    let peakHours:        String
    let popularDrinks:    [PopularDrink]
    let upcomingEvents:   [VenueEvent]
    let tags:             [String]
    let emoji:            String
    let instagramHandle:  String?
    var isTrending:       Bool
    var hasHappyHour:     Bool
    var happyHourUntil:   String?
    var isOpenNow:        Bool

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
}
