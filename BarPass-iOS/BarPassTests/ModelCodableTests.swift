import XCTest
@testable import BarPass_app

/// Round-trip Codable tests — la excusa de "parsing/data-loading" que pidió
/// el plan de testing. Estos cachean a disco (VenueStore offline cache,
/// AppleMusicPlaybackService song-ID cache) y a Supabase; un cambio de campo
/// que rompa el encode/decode se detecta acá antes de romper producción.
final class ModelCodableTests: XCTestCase {

    func test_barPassVenue_roundTripsThroughJSON() throws {
        let venue = BarPassVenue(
            id: "v1", name: "Test Venue", neighborhood: "Wynwood", address: "123 Main St",
            latitude: 25.8, longitude: -80.2, type: .club, vibes: ["upscale"],
            musicGenres: [.edm, .house], rating: 4.7, reviewCount: 120,
            coverMen: 40, coverWomen: 20, openTime: "22:00", closeTime: "04:00",
            avgSpend: "$$$", dressCode: "Upscale", parking: "Valet", crowdLevel: 8,
            bestArrivalTime: "23:00", peakHours: "00:00-02:00",
            popularDrinks: [PopularDrink(id: "d1", name: "Mojito", price: 18, emoji: "🍹")],
            upcomingEvents: [], tags: ["trending"], emoji: "🎉",
            instagramHandle: "@testvenue", isTrending: true, hasHappyHour: false,
            happyHourUntil: nil, isOpenNow: true, photoUrls: ["https://example.com/a.jpg"],
            editorial: nil
        )

        let data = try JSONEncoder().encode(venue)
        let decoded = try JSONDecoder().decode(BarPassVenue.self, from: data)

        XCTAssertEqual(decoded.id, venue.id)
        XCTAssertEqual(decoded.musicGenres, venue.musicGenres)
        XCTAssertEqual(decoded.popularDrinks.first?.name, "Mojito")
        XCTAssertEqual(decoded.coverMen, 40)
    }

    func test_barPassVenue_decodesWithNilOptionals() throws {
        // Confirma que campos opcionales realmente pueden faltar sin crashear
        // el decode — cover gratis, sin happy hour, sin Instagram, etc.
        let venue = BarPassVenue(
            id: "v2", name: "Free Cover Bar", neighborhood: "Brickell", address: "",
            latitude: 0, longitude: 0, type: .bar, vibes: [], musicGenres: [],
            rating: 4.0, reviewCount: 0, coverMen: nil, coverWomen: nil,
            openTime: "18:00", closeTime: "02:00", avgSpend: "$", dressCode: "",
            parking: "", crowdLevel: 3, bestArrivalTime: "", peakHours: "",
            popularDrinks: [], upcomingEvents: [], tags: [], emoji: "🍺",
            instagramHandle: nil, isTrending: false, hasHappyHour: false,
            happyHourUntil: nil, isOpenNow: false, photoUrls: [], editorial: nil
        )

        let data = try JSONEncoder().encode(venue)
        let decoded = try JSONDecoder().decode(BarPassVenue.self, from: data)
        XCTAssertNil(decoded.coverMen)
        XCTAssertNil(decoded.instagramHandle)
    }

    func test_musicPassport_roundTripsThroughJSON() throws {
        let passport = MusicPassport(
            topGenres: [GenreWeight(genre: "house", weight: 0.6)],
            topArtists: [ArtistPlay(name: "Test Artist", plays: 5, genres: ["house"], imageURL: nil)],
            hypeScore: 72, energy: 60, nightPersonality: "Night Explorer",
            newDiscoveries: ["New Artist"], sources: [.appleMusic, .spotify],
            updatedAt: Date()
        )

        let data = try JSONEncoder().encode(passport)
        let decoded = try JSONDecoder().decode(MusicPassport.self, from: data)

        XCTAssertEqual(decoded.hypeScore, 72)
        XCTAssertEqual(decoded.sources, [.appleMusic, .spotify])
        XCTAssertEqual(decoded.topArtists.first?.name, "Test Artist")
    }
}
