import XCTest
@testable import BarPass_app

/// HypeEngine es la lógica más frágil y más reescrita de toda la sesión de
/// hoy (bug del match 0% en silencio, playlist de 1 canción, etc.) — es el
/// primer candidato real para tests: pura, determinística, sin I/O.
final class HypeEngineTests: XCTestCase {

    private func snapshot(
        artists: [(String, Int)],
        genres: [(String, Double)],
        source: MusicSourceKind = .appleMusic
    ) -> MusicSnapshot {
        MusicSnapshot(
            artists: artists.map { ArtistPlay(name: $0.0, plays: $0.1, genres: [], imageURL: nil) },
            genres: genres.map { GenreWeight(genre: $0.0, weight: $0.1) },
            capturedAt: Date(),
            source: source
        )
    }

    private func passport(topGenres: [(String, Double)]) -> MusicPassport {
        MusicPassport(
            topGenres: topGenres.map { GenreWeight(genre: $0.0, weight: $0.1) },
            topArtists: [],
            hypeScore: 0,
            energy: 0,
            nightPersonality: "",
            newDiscoveries: [],
            sources: [.appleMusic],
            updatedAt: Date()
        )
    }

    private func venue(genres: [MusicGenre]) -> BarPassVenue {
        BarPassVenue(
            id: "v1", name: "Test Venue", neighborhood: "Wynwood", address: "",
            latitude: 0, longitude: 0, type: .club, vibes: [], musicGenres: genres,
            rating: 4.5, reviewCount: 10, coverMen: nil, coverWomen: nil,
            openTime: "22:00", closeTime: "04:00", avgSpend: "$$", dressCode: "",
            parking: "", crowdLevel: 5, bestArrivalTime: "", peakHours: "",
            popularDrinks: [], upcomingEvents: [], tags: [], emoji: "🎉",
            instagramHandle: nil, isTrending: false, hasHappyHour: false,
            happyHourUntil: nil, isOpenNow: true, photoUrls: [], editorial: nil
        )
    }

    // MARK: - compute()

    func test_compute_higherConcentration_yieldsHigherHype() {
        let concentrated = snapshot(artists: [("A", 20), ("B", 1), ("C", 1)], genres: [("house", 1.0)])
        let spread = snapshot(artists: [("A", 5), ("B", 5), ("C", 5), ("D", 5)], genres: [("house", 1.0)])

        let a = HypeEngine.compute(concentrated, previous: nil)
        let b = HypeEngine.compute(spread, previous: nil)

        XCTAssertGreaterThan(a.hypeScore, b.hypeScore)
    }

    func test_compute_energyReflectsGenreWeights() {
        let highEnergy = snapshot(artists: [("A", 1)], genres: [("edm", 1.0)])
        let lowEnergy = snapshot(artists: [("A", 1)], genres: [("jazz", 1.0)])

        XCTAssertGreaterThan(HypeEngine.compute(highEnergy, previous: nil).energy,
                              HypeEngine.compute(lowEnergy, previous: nil).energy)
    }

    func test_compute_firstTimeSnapshot_doesNotInflateDiscoveryRatio() {
        // previous == nil debe ser neutro (0.5), no tratar todo como "descubrimiento nuevo".
        let snap = snapshot(artists: [("A", 1), ("B", 1)], genres: [("pop", 1.0)])
        let result = HypeEngine.compute(snap, previous: nil)
        XCTAssertEqual(result.newDiscoveries.count, 0, "sin snapshot previo no hay base de comparación real")
    }

    func test_compute_detectsRealDiscoveries() {
        let previous = snapshot(artists: [("A", 5)], genres: [("pop", 1.0)])
        let current = snapshot(artists: [("A", 5), ("NewArtist", 3)], genres: [("pop", 1.0)])
        let result = HypeEngine.compute(current, previous: previous)
        XCTAssertTrue(result.newDiscoveries.contains("NewArtist"))
        XCTAssertFalse(result.newDiscoveries.contains("A"))
    }

    // MARK: - merge()

    func test_merge_singleSnapshot_returnsUnchanged() {
        let snap = snapshot(artists: [("A", 5)], genres: [("house", 1.0)])
        XCTAssertEqual(HypeEngine.merge([snap])?.artists.count, 1)
    }

    func test_merge_combinesPlaysAcrossSources_caseInsensitive() {
        let apple = snapshot(artists: [("Drake", 10)], genres: [("hip-hop", 1.0)], source: .appleMusic)
        let spotify = snapshot(artists: [("drake", 5)], genres: [("hip-hop", 1.0)], source: .spotify)

        let merged = HypeEngine.merge([apple, spotify])
        XCTAssertEqual(merged?.artists.count, 1, "mismo artista en distinto casing debe fusionarse en una sola entrada")
        XCTAssertEqual(merged?.artists.first?.plays, 15)
    }

    func test_merge_emptyArray_returnsNil() {
        XCTAssertNil(HypeEngine.merge([]))
    }

    // MARK: - musicMatch() / genre synonyms

    func test_musicMatch_directGenreOverlap_scoresAboveZero() {
        let p = passport(topGenres: [("edm", 1.0)])
        let v = venue(genres: [.edm])
        XCTAssertGreaterThan(HypeEngine.musicMatch(passport: p, venue: v), 0)
    }

    func test_musicMatch_rockMapsToLiveViaSynonyms() {
        // Bug real de hoy: "rock"/"country" no existían en el vocabulario de
        // venue.musicGenres — sin la tabla de sinónimos, esto daba 0 en TODOS
        // los venues, en silencio.
        let p = passport(topGenres: [("rock", 1.0)])
        let v = venue(genres: [.live])
        XCTAssertGreaterThan(HypeEngine.musicMatch(passport: p, venue: v), 0,
                              "rock debe mapear a .live vía genreSynonyms, no dar 0 silencioso")
    }

    func test_musicMatch_noOverlap_scoresZero() {
        let p = passport(topGenres: [("classical", 1.0)])
        let v = venue(genres: [.edm])
        XCTAssertEqual(HypeEngine.musicMatch(passport: p, venue: v), 0)
    }

    func test_musicMatch_emptyPassportGenres_scoresZero() {
        let p = passport(topGenres: [])
        let v = venue(genres: [.edm])
        XCTAssertEqual(HypeEngine.musicMatch(passport: p, venue: v), 0)
    }

    func test_musicMatch_neverExceedsOne() {
        let p = passport(topGenres: [("edm", 0.5), ("house", 0.5)])
        let v = venue(genres: [.edm, .house])
        XCTAssertLessThanOrEqual(HypeEngine.musicMatch(passport: p, venue: v), 1.0)
    }

    // MARK: - musicMatchTier() — no debe mostrar falsa precisión

    func test_musicMatchTier_belowThreshold_returnsNil() {
        let p = passport(topGenres: [("classical", 1.0)])
        let v = venue(genres: [.edm])
        XCTAssertNil(HypeEngine.musicMatchTier(passport: p, venue: v))
    }

    func test_musicMatchTier_strongOverlap_returnsExcellent() {
        let p = passport(topGenres: [("edm", 0.6), ("house", 0.4)])
        let v = venue(genres: [.edm, .house])
        XCTAssertEqual(HypeEngine.musicMatchTier(passport: p, venue: v), .excellent)
    }

    // MARK: - matchedVenues()

    func test_matchedVenues_excludesBelowMinScore() {
        let p = passport(topGenres: [("edm", 1.0)])
        let matching = venue(genres: [.edm])
        let nonMatching = venue(genres: [.jazz])
        let result = HypeEngine.matchedVenues(passport: p, venues: [matching, nonMatching])
        XCTAssertEqual(result.count, 1)
    }

    func test_matchedVenues_sortedByScoreDescending() {
        let p = passport(topGenres: [("edm", 0.7), ("house", 0.3)])
        let strong = venue(genres: [.edm, .house])
        let weak = venue(genres: [.edm])
        let result = HypeEngine.matchedVenues(passport: p, venues: [weak, strong], minScore: 0.01)
        XCTAssertEqual(result.first?.musicGenres, strong.musicGenres)
    }
}
