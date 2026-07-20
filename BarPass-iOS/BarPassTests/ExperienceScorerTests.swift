import XCTest
@testable import BarPass_app

/// Permanent regression net for `ExperienceScorer` — the second time a
/// throwaway `/tmp` harness was built to validate this exact logic and lost
/// between sessions. Fixed, in-memory venue fixtures — no live Supabase
/// fetch — so this runs offline and never depends on the current state of
/// the real 181-venue catalog.
final class ExperienceScorerTests: XCTestCase {

    // MARK: - Fixtures

    private func venue(
        id: String,
        type: VenueType,
        rating: Double = 4.5,
        isTrending: Bool = false,
        musicGenres: [MusicGenre] = [],
        experienceTags: [ExperienceTag] = []
    ) -> BarPassVenue {
        var v = BarPassVenue(
            id: id, name: "Venue \(id)", neighborhood: "Wynwood", address: "",
            latitude: 0, longitude: 0, type: type, vibes: [], musicGenres: musicGenres,
            rating: rating, reviewCount: 100, coverMen: nil, coverWomen: nil,
            openTime: "22:00", closeTime: "04:00", avgSpend: "$$", dressCode: "",
            parking: "", crowdLevel: 3, bestArrivalTime: "", peakHours: "",
            popularDrinks: [], upcomingEvents: [], tags: [], emoji: "🍸",
            instagramHandle: nil, isTrending: isTrending, hasHappyHour: false,
            happyHourUntil: nil, isOpenNow: true, photoUrls: [], editorial: nil
        )
        v.experienceTags = experienceTags
        return v
    }

    private func tag(_ id: String, _ confidence: TagConfidence) -> ExperienceTag {
        ExperienceTag(id: id, category: "test", confidence: confidence, source: .googleAttribute)
    }

    private func context(intent: ExperienceIntent, company: CompanyType? = nil, durationHours: Double? = nil) -> TripContext {
        TripContext(intents: [intent.id], company: company, durationHours: durationHours)
    }

    // MARK: - Scenario 1: celebrate + friends
    // (recreates the "1. Celebrar con amigos" scenario from the
    // conflictingTagIds validation session — a group_night club should
    // outrank a plain bar with no matching signals.)

    func test_celebrate_groupNightClub_outranksPlainBar() {
        let club = venue(id: "club", type: .club, experienceTags: [tag("group_night", .high)])
        let plainBar = venue(id: "bar", type: .bar)
        let ctx = context(intent: .celebrate, company: .friends)

        let clubScore = ExperienceScorer.score(venue: club, context: ctx)
        let barScore = ExperienceScorer.score(venue: plainBar, context: ctx)

        XCTAssertGreaterThan(clubScore, barScore)
    }

    // MARK: - Scenario 2: relax + couple, the validated conflictingTagIds bug
    // (recreates "2. Algo relajado en pareja" — a high_energy club must NOT
    // outrank a calmer venue just because it also has an outdoor tag. This
    // is the literal regression the conflictingTagIds fix closed.)

    func test_relax_conflictingHighEnergyTag_scoresLowerThanPositiveOnly() {
        let calmBar = venue(id: "calm", type: .bar, experienceTags: [tag("outdoor_experience", .high)])
        let highEnergyClub = venue(id: "loud", type: .club, experienceTags: [
            tag("outdoor_experience", .high),
            tag("high_energy", .medium),
        ])
        let ctx = context(intent: .relax, company: .couple)

        let calmScore = ExperienceScorer.score(venue: calmBar, context: ctx)
        let loudScore = ExperienceScorer.score(venue: highEnergyClub, context: ctx)

        // Same positive tag on both — the only difference is the conflicting
        // tag, so the calmer venue (no conflict) must win.
        XCTAssertGreaterThan(calmScore, loudScore,
            "a venue matching both a positive and a conflicting tag for the same intent must score lower than one matching only the positive tag")
    }

    // MARK: - Scenario 3: watchSports + friends, 2h duration
    // (recreates "3. Ver deportes con amigos, 2hs" — a sports_viewing venue
    // should outrank one with no sports signal at all.)

    func test_watchSports_sportsViewingVenue_outranksNonSportsVenue() {
        let sportsBar = venue(id: "sports", type: .sportsBar, experienceTags: [tag("sports_viewing", .high)])
        let randomBar = venue(id: "random", type: .bar)
        let ctx = context(intent: .watchSports, company: .friends, durationHours: 2.0)

        let sportsScore = ExperienceScorer.score(venue: sportsBar, context: ctx)
        let randomScore = ExperienceScorer.score(venue: randomBar, context: ctx)

        XCTAssertGreaterThan(sportsScore, randomScore)
    }

    // MARK: - No-passport case

    func test_score_withNoPassport_isNonzeroAndFinite() {
        let v = venue(id: "v", type: .bar, rating: 4.2, isTrending: true)
        let score = ExperienceScorer.score(venue: v, context: TripContext())

        XCTAssertGreaterThan(score, 0)
        XCTAssertFalse(score.isNaN)
        XCTAssertFalse(score.isInfinite)
    }

    // MARK: - With-passport case (Home Feed's recommendedForYou claim)

    func test_score_withMatchingPassport_scoresHigherThanNoPassport() {
        let v = venue(id: "v", type: .bar, musicGenres: [.edm])
        let passport = MusicPassport(
            topGenres: [GenreWeight(genre: "edm", weight: 1.0)],
            topArtists: [], hypeScore: 0, energy: 0, nightPersonality: "",
            newDiscoveries: [], sources: [.appleMusic], updatedAt: Date()
        )

        let withoutPassport = ExperienceScorer.score(venue: v, passport: nil, context: TripContext())
        let withPassport = ExperienceScorer.score(venue: v, passport: passport, context: TripContext())

        XCTAssertGreaterThan(withPassport, withoutPassport,
            "a venue whose genres overlap the passport's top genres must score higher than the same venue scored with no passport at all")
    }

    func test_score_withNonMatchingPassport_scoresNoHigherThanNoPassport() {
        let v = venue(id: "v", type: .bar, musicGenres: [.jazz])
        let passport = MusicPassport(
            topGenres: [GenreWeight(genre: "edm", weight: 1.0)],
            topArtists: [], hypeScore: 0, energy: 0, nightPersonality: "",
            newDiscoveries: [], sources: [.appleMusic], updatedAt: Date()
        )

        let withoutPassport = ExperienceScorer.score(venue: v, passport: nil, context: TripContext())
        let withNonMatchingPassport = ExperienceScorer.score(venue: v, passport: passport, context: TripContext())

        XCTAssertEqual(withNonMatchingPassport, withoutPassport,
            "a passport with zero genre overlap must not change the score at all")
    }
}
