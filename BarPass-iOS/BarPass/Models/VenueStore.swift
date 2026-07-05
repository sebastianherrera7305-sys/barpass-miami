import Foundation

@MainActor
final class VenueStore: ObservableObject {
    @Published var venues: [Venue] = VenueStore.miamVenues
    @Published var searchText = ""
    @Published var selectedNeighborhood: String? = nil
    @Published var selectedType: VenueType? = nil

    var trending: [Venue]    { venues.filter { $0.isTrending } }
    var openNow:  [Venue]    { venues.filter { $0.isOpenNow } }
    var happyHour:[Venue]    { venues.filter { $0.hasHappyHour } }

    var neighborhoods: [String] {
        Array(Set(venues.map { $0.neighborhood })).sorted()
    }

    func venues(for tag: String) -> [Venue] {
        venues.filter { $0.tags.contains(tag) || $0.vibes.contains(tag) }
    }

    func filtered(by query: String) -> [Venue] {
        guard !query.isEmpty else { return venues }
        return venues.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.neighborhood.localizedCaseInsensitiveContains(query) ||
            $0.tags.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    // MARK: - Miami Data

    static let miamVenues: [Venue] = [
        Venue(
            id: "liv-miami",
            name: "LIV Miami",
            neighborhood: "South Beach",
            address: "4441 Collins Ave, Miami Beach",
            type: .club,
            vibes: ["VIP", "Luxury", "Bottle Service", "Celebrity"],
            musicGenres: [.edm, .hipHop, .pop],
            rating: 4.6,
            reviewCount: 3840,
            coverMen: 40,
            coverWomen: 20,
            openTime: "11:00 PM",
            closeTime: "5:00 AM",
            avgSpend: "$150–400",
            dressCode: "Upscale — no sneakers, no shorts",
            parking: "Valet $30 · Hotel parking available",
            crowdLevel: 4,
            bestArrivalTime: "11:30 PM – 12:30 AM",
            peakHours: "1:00 AM – 3:00 AM",
            popularDrinks: [
                PopularDrink(id: "1", name: "Grey Goose Bottle", price: 350, emoji: "🍾"),
                PopularDrink(id: "2", name: "Don Julio 1942",    price: 600, emoji: "🥃"),
                PopularDrink(id: "3", name: "Ace of Spades",     price: 800, emoji: "🥂"),
            ],
            upcomingEvents: [
                VenueEvent(id: "e1", title: "Cedric Gervais",   date: Date().addingTimeInterval(86400),    coverPrice: 45, description: "Residency night"),
                VenueEvent(id: "e2", title: "Foam Party",        date: Date().addingTimeInterval(172800),  coverPrice: 0,  description: "Free before 12am"),
            ],
            tags: ["EDM", "VIP", "Nightclub", "18+", "South Beach", "Celebrity"],
            emoji: "🔥",
            instagramHandle: "livmiami",
            isTrending: true,
            hasHappyHour: false,
            happyHourUntil: nil,
            isOpenNow: true
        ),
        Venue(
            id: "e11even",
            name: "E11EVEN Miami",
            neighborhood: "Downtown",
            address: "29 NE 11th St, Miami",
            type: .club,
            vibes: ["24/7", "Wild", "Multi-Floor", "Showgirls", "EDM"],
            musicGenres: [.edm, .house, .hipHop],
            rating: 4.5,
            reviewCount: 5200,
            coverMen: 30,
            coverWomen: 20,
            openTime: "11:00 PM",
            closeTime: "11:00 PM",
            avgSpend: "$100–300",
            dressCode: "Fashion forward — creative welcome",
            parking: "Valet $25 · Garage nearby",
            crowdLevel: 5,
            bestArrivalTime: "12:00 AM – 1:00 AM",
            peakHours: "2:00 AM – 6:00 AM",
            popularDrinks: [
                PopularDrink(id: "1", name: "Tito's Bottle",     price: 280, emoji: "🍾"),
                PopularDrink(id: "2", name: "Belvedere Bottle",  price: 320, emoji: "🍾"),
                PopularDrink(id: "3", name: "Hennessy VS",       price: 350, emoji: "🥃"),
            ],
            upcomingEvents: [
                VenueEvent(id: "e1", title: "Sunday Session", date: Date().addingTimeInterval(259200), coverPrice: 25, description: "Open 24/7 · Never closes"),
            ],
            tags: ["24/7", "EDM", "Downtown", "Wild", "Multi-Floor", "18+"],
            emoji: "⚡",
            instagramHandle: "e11evenmia",
            isTrending: true,
            hasHappyHour: false,
            happyHourUntil: nil,
            isOpenNow: true
        ),
        Venue(
            id: "space-miami",
            name: "Space Miami",
            neighborhood: "Downtown",
            address: "34 NE 11th St, Miami",
            type: .club,
            vibes: ["Underground", "Techno", "House", "After Hours"],
            musicGenres: [.techHouse, .house, .edm],
            rating: 4.7,
            reviewCount: 2900,
            coverMen: 25,
            coverWomen: 15,
            openTime: "11:00 PM",
            closeTime: "12:00 PM",
            avgSpend: "$80–200",
            dressCode: "Casual chic — sneakers ok",
            parking: "Street · Garage on 12th",
            crowdLevel: 4,
            bestArrivalTime: "12:30 AM – 2:00 AM",
            peakHours: "3:00 AM – 8:00 AM",
            popularDrinks: [
                PopularDrink(id: "1", name: "Heineken",        price: 12,  emoji: "🍺"),
                PopularDrink(id: "2", name: "Patron Bottle",   price: 380, emoji: "🍾"),
                PopularDrink(id: "3", name: "Vodka Red Bull",  price: 18,  emoji: "🥤"),
            ],
            upcomingEvents: [],
            tags: ["Techno", "House", "Underground", "After Hours", "Downtown"],
            emoji: "🎵",
            instagramHandle: "spacemiami",
            isTrending: false,
            hasHappyHour: false,
            happyHourUntil: nil,
            isOpenNow: false
        ),
        Venue(
            id: "sugar-rooftop",
            name: "Sugar",
            neighborhood: "Brickell",
            address: "788 Brickell Plaza, 40th Floor",
            type: .rooftop,
            vibes: ["Rooftop", "Views", "Chill", "Date Night", "Asian-inspired"],
            musicGenres: [.house, .pop, .rnb],
            rating: 4.8,
            reviewCount: 4100,
            coverMen: 20,
            coverWomen: 20,
            openTime: "6:00 PM",
            closeTime: "3:00 AM",
            avgSpend: "$60–150",
            dressCode: "Smart casual",
            parking: "Valet · Building garage",
            crowdLevel: 3,
            bestArrivalTime: "7:00 PM – 9:00 PM",
            peakHours: "10:00 PM – 1:00 AM",
            popularDrinks: [
                PopularDrink(id: "1", name: "Sugar Rush Cocktail", price: 22, emoji: "🍹"),
                PopularDrink(id: "2", name: "Sake Bomb",           price: 18, emoji: "🍶"),
                PopularDrink(id: "3", name: "Bao Bao Spritz",      price: 20, emoji: "🥂"),
            ],
            upcomingEvents: [],
            tags: ["Rooftop", "Brickell", "Date Night", "Views", "Sunset", "Chill"],
            emoji: "🌆",
            instagramHandle: "sugarbrickell",
            isTrending: true,
            hasHappyHour: true,
            happyHourUntil: "8:00 PM",
            isOpenNow: true
        ),
        Venue(
            id: "the-wharf",
            name: "The Wharf Miami",
            neighborhood: "Brickell",
            address: "114 SW North River Dr",
            type: .bar,
            vibes: ["Outdoor", "Waterfront", "Casual", "Sports", "Chill"],
            musicGenres: [.pop, .hipHop, .live],
            rating: 4.5,
            reviewCount: 6800,
            coverMen: 0,
            coverWomen: 0,
            openTime: "4:00 PM",
            closeTime: "3:00 AM",
            avgSpend: "$30–80",
            dressCode: "Casual — anything goes",
            parking: "Street · Garage on Brickell",
            crowdLevel: 3,
            bestArrivalTime: "6:00 PM – 8:00 PM",
            peakHours: "9:00 PM – 12:00 AM",
            popularDrinks: [
                PopularDrink(id: "1", name: "Frozen Daiquiri",  price: 14, emoji: "🍓"),
                PopularDrink(id: "2", name: "Craft Beer",       price: 10, emoji: "🍺"),
                PopularDrink(id: "3", name: "Miami Mule",       price: 15, emoji: "🍹"),
            ],
            upcomingEvents: [],
            tags: ["No Cover", "Outdoor", "Waterfront", "Brickell", "Casual", "Food"],
            emoji: "⛵",
            instagramHandle: "thewharfmiami",
            isTrending: false,
            hasHappyHour: true,
            happyHourUntil: "7:00 PM",
            isOpenNow: true
        ),
        Venue(
            id: "ball-chain",
            name: "Ball & Chain",
            neighborhood: "Little Havana",
            address: "1513 SW 8th St, Miami",
            type: .lounge,
            vibes: ["Latin", "Jazz", "Live Music", "Historic", "Cuban"],
            musicGenres: [.latin, .jazz, .live],
            rating: 4.7,
            reviewCount: 3200,
            coverMen: 10,
            coverWomen: 10,
            openTime: "3:00 PM",
            closeTime: "3:00 AM",
            avgSpend: "$40–90",
            dressCode: "Casual to smart casual",
            parking: "Street parking available",
            crowdLevel: 3,
            bestArrivalTime: "8:00 PM – 10:00 PM",
            peakHours: "10:00 PM – 1:00 AM",
            popularDrinks: [
                PopularDrink(id: "1", name: "Mojito",       price: 14, emoji: "🍃"),
                PopularDrink(id: "2", name: "Cuba Libre",   price: 12, emoji: "🥃"),
                PopularDrink(id: "3", name: "Daiquiri",     price: 13, emoji: "🍹"),
            ],
            upcomingEvents: [
                VenueEvent(id: "e1", title: "Salsa Night", date: Date().addingTimeInterval(86400), coverPrice: 10, description: "Live band every Friday"),
            ],
            tags: ["Latin", "Live Music", "Cultural", "Little Havana", "Jazz", "Cuban"],
            emoji: "🎺",
            instagramHandle: "ballandchainmiami",
            isTrending: false,
            hasHappyHour: true,
            happyHourUntil: "7:00 PM",
            isOpenNow: true
        ),
        Venue(
            id: "wynwood-garage",
            name: "Wynwood Garage",
            neighborhood: "Wynwood",
            address: "212 NW 24th St, Miami",
            type: .bar,
            vibes: ["Art", "Hip", "Outdoor", "Local", "Creative"],
            musicGenres: [.hipHop, .rnb, .techHouse],
            rating: 4.4,
            reviewCount: 1800,
            coverMen: 0,
            coverWomen: 0,
            openTime: "5:00 PM",
            closeTime: "2:00 AM",
            avgSpend: "$25–60",
            dressCode: "Creative — anything",
            parking: "Street parking",
            crowdLevel: 2,
            bestArrivalTime: "7:00 PM – 9:00 PM",
            peakHours: "10:00 PM – 1:00 AM",
            popularDrinks: [
                PopularDrink(id: "1", name: "Local Craft IPA", price: 10, emoji: "🍺"),
                PopularDrink(id: "2", name: "Wynwood Punch",   price: 14, emoji: "🍹"),
            ],
            upcomingEvents: [],
            tags: ["No Cover", "Wynwood", "Art", "Outdoor", "Local", "Hidden Gem"],
            emoji: "🎨",
            instagramHandle: "wynwoodgarage",
            isTrending: false,
            hasHappyHour: true,
            happyHourUntil: "8:00 PM",
            isOpenNow: true
        ),
        Venue(
            id: "komodo",
            name: "Komodo",
            neighborhood: "Brickell",
            address: "801 Brickell Ave, Miami",
            type: .restaurant,
            vibes: ["Luxury", "Asian-Fusion", "Upscale", "Date Night", "Beautiful People"],
            musicGenres: [.house, .pop, .rnb],
            rating: 4.6,
            reviewCount: 5600,
            coverMen: nil,
            coverWomen: nil,
            openTime: "6:00 PM",
            closeTime: "2:00 AM",
            avgSpend: "$80–200",
            dressCode: "Upscale — no sneakers",
            parking: "Valet $20",
            crowdLevel: 3,
            bestArrivalTime: "7:00 PM – 9:00 PM",
            peakHours: "9:00 PM – 12:00 AM",
            popularDrinks: [
                PopularDrink(id: "1", name: "Dragon Lychee Martini", price: 22, emoji: "🍸"),
                PopularDrink(id: "2", name: "Komodo Old Fashioned",  price: 24, emoji: "🥃"),
            ],
            upcomingEvents: [],
            tags: ["Dinner", "Brickell", "Luxury", "Date Night", "Asian-Fusion", "Restaurant"],
            emoji: "🐉",
            instagramHandle: "komodomiami",
            isTrending: true,
            hasHappyHour: false,
            happyHourUntil: nil,
            isOpenNow: true
        ),
    ]
}
