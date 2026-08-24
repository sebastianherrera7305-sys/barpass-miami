import XCTest
import CoreLocation
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
        experienceTags: [ExperienceTag] = [],
        slug: String? = nil,
        latitude: Double = 0,
        longitude: Double = 0,
        isOpenNow: Bool = true,
        upcomingEvents: [VenueEvent] = [],
        reviewCount: Int = 100
    ) -> BarPassVenue {
        var v = BarPassVenue(
            id: id, name: "Venue \(id)", neighborhood: "Wynwood", address: "",
            latitude: latitude, longitude: longitude, type: type, vibes: [], musicGenres: musicGenres,
            rating: rating, reviewCount: reviewCount, coverMen: nil, coverWomen: nil,
            openTime: "22:00", closeTime: "04:00", avgSpend: "$$", dressCode: "",
            parking: "", crowdLevel: 3, bestArrivalTime: "", peakHours: "",
            popularDrinks: [], upcomingEvents: upcomingEvents, tags: [], emoji: "🍸",
            instagramHandle: nil, isTrending: isTrending, hasHappyHour: false,
            happyHourUntil: nil, isOpenNow: isOpenNow, photoUrls: [], editorial: nil,
            slug: slug
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

    // MARK: - Test date helper — real upcoming weekday/hour, never hardcoded
    // against an assumed calendar (a hardcoded "2026-08-14 is a Friday"
    // string breaks the moment someone edits it without checking).

    /// weekday: 1=Sun ... 6=Fri, 7=Sat, per `Calendar.component(.weekday:)`.
    private func dateFor(weekday: Int, hour: Int) -> Date {
        var comps = DateComponents()
        comps.weekday = weekday
        comps.hour = hour
        comps.minute = 0
        return Calendar.current.nextDate(after: Date(), matching: comps, matchingPolicy: .nextTime)!
    }

    // MARK: - Weekday/curation boost (Fase 2 — college nightlife curation)

    func test_fridayNight_curatedVenue_outranksSameVenueUncurated() {
        let curated = venue(id: "curated", type: .club, slug: "club-space")
        let uncurated = venue(id: "plain", type: .club, slug: "not-in-the-list")
        let fridayNight = dateFor(weekday: 6, hour: 22)

        let curatedScore = ExperienceScorer.score(venue: curated, context: TripContext(), now: fridayNight)
        let uncuratedScore = ExperienceScorer.score(venue: uncurated, context: TripContext(), now: fridayNight)

        XCTAssertGreaterThan(curatedScore, uncuratedScore)
    }

    func test_saturdayNight_curatedVenue_outranksSameVenueUncurated() {
        let curated = venue(id: "curated", type: .bar, slug: "the-bar")
        let uncurated = venue(id: "plain", type: .bar, slug: "not-in-the-list")
        let saturdayNight = dateFor(weekday: 7, hour: 2)

        let curatedScore = ExperienceScorer.score(venue: curated, context: TripContext(), now: saturdayNight)
        let uncuratedScore = ExperienceScorer.score(venue: uncurated, context: TripContext(), now: saturdayNight)

        XCTAssertGreaterThan(curatedScore, uncuratedScore)
    }

    func test_tuesdayNight_curatedVenue_getsNoWeekdayBoost() {
        // The curation boost is gated on Thu/Fri/Sat — a curated venue on a
        // Tuesday must score identically to the same venue if it weren't
        // curated at all, proving the gate actually gates.
        let curated = venue(id: "curated", type: .club, slug: "club-space")
        let uncurated = venue(id: "plain", type: .club, slug: "not-in-the-list")
        let tuesdayNight = dateFor(weekday: 3, hour: 22)

        let curatedScore = ExperienceScorer.score(venue: curated, context: TripContext(), now: tuesdayNight)
        let uncuratedScore = ExperienceScorer.score(venue: uncurated, context: TripContext(), now: tuesdayNight)

        XCTAssertEqual(curatedScore, uncuratedScore, accuracy: 0.0001)
    }

    // MARK: - Real event tiers

    func test_venueWithEventToday_outranksVenueWithNoEvent() {
        let now = Date()
        let withEvent = venue(id: "hasEvent", type: .club, upcomingEvents: [
            VenueEvent(id: "e1", title: "Real Show", date: now.addingTimeInterval(3600), coverPrice: nil, description: "")
        ])
        let noEvent = venue(id: "noEvent", type: .club)

        let withEventScore = ExperienceScorer.score(venue: withEvent, context: TripContext(), now: now)
        let noEventScore = ExperienceScorer.score(venue: noEvent, context: TripContext(), now: now)

        XCTAssertGreaterThan(withEventScore, noEventScore)
    }

    func test_eventStartingSoon_outranksSameVenueWithEventStartingLater() {
        let now = Date()
        let soon = venue(id: "soon", type: .club, upcomingEvents: [
            VenueEvent(id: "e1", title: "Starts Soon", date: now.addingTimeInterval(30 * 60), coverPrice: nil, description: "")
        ])
        let later = venue(id: "later", type: .club, upcomingEvents: [
            VenueEvent(id: "e2", title: "Starts Later", date: now.addingTimeInterval(10 * 3600), coverPrice: nil, description: "")
        ])

        let soonScore = ExperienceScorer.score(venue: soon, context: TripContext(), now: now)
        let laterScore = ExperienceScorer.score(venue: later, context: TripContext(), now: now)

        XCTAssertGreaterThan(soonScore, laterScore,
            "an event starting within 3h must outrank one starting outside that window, both real events on real venues")
    }

    func test_liveEventNow_outranksUpcomingEvent() {
        let now = Date()
        let live = venue(id: "live", type: .club, upcomingEvents: [
            VenueEvent(id: "e1", title: "Live Now", date: now.addingTimeInterval(-1800), coverPrice: nil, description: "")
        ])
        let upcoming = venue(id: "upcoming", type: .club, upcomingEvents: [
            VenueEvent(id: "e2", title: "Starting Soon", date: now.addingTimeInterval(600), coverPrice: nil, description: "")
        ])

        let liveScore = ExperienceScorer.score(venue: live, context: TripContext(), now: now)
        let upcomingScore = ExperienceScorer.score(venue: upcoming, context: TripContext(), now: now)

        XCTAssertGreaterThan(liveScore, upcomingScore)
    }

    // MARK: - Personalization (real FavoritesStore signal, never a guessed profile)

    func test_userWithFavoriteType_boostsMatchingTypeVenue() {
        let rooftop = venue(id: "roof", type: .rooftop)
        let bar = venue(id: "bar", type: .bar)

        let withFavorites = ExperienceScorer.score(venue: rooftop, context: TripContext(), favoriteTypes: [.rooftop])
        let withoutFavorites = ExperienceScorer.score(venue: rooftop, context: TripContext(), favoriteTypes: [])
        let barWithRooftopFavorite = ExperienceScorer.score(venue: bar, context: TripContext(), favoriteTypes: [.rooftop])

        XCTAssertGreaterThan(withFavorites, withoutFavorites)
        // A rooftop-favoriting user's boost must be type-specific — it
        // shouldn't leak onto an unrelated bar.
        XCTAssertEqual(barWithRooftopFavorite, ExperienceScorer.score(venue: bar, context: TripContext(), favoriteTypes: []), accuracy: 0.0001)
    }

    func test_userWithNoHistory_getsZeroPersonalizationContribution() {
        let v = venue(id: "v", type: .bar)
        let withEmptyFavorites = ExperienceScorer.score(venue: v, context: TripContext(), favoriteTypes: [])
        let withNoFavoritesParamAtAll = ExperienceScorer.score(venue: v, context: TripContext())

        XCTAssertEqual(withEmptyFavorites, withNoFavoritesParamAtAll, accuracy: 0.0001)
    }

    // MARK: - Distance (real haversine, never a guessed location)

    func test_nearbyVenue_outranksFarVenue_whenUserLocationKnown() {
        let userCoord = CLLocationCoordinate2D(latitude: 25.7617, longitude: -80.1918) // Downtown Miami
        let nearby = venue(id: "near", type: .bar, latitude: 25.7650, longitude: -80.1950) // ~0.5km away
        let far = venue(id: "far", type: .bar, latitude: 25.9000, longitude: -80.3000) // ~20km away

        let nearScore = ExperienceScorer.score(venue: nearby, context: TripContext(), userCoordinate: userCoord)
        let farScore = ExperienceScorer.score(venue: far, context: TripContext(), userCoordinate: userCoord)

        XCTAssertGreaterThan(nearScore, farScore)
    }

    func test_noUserLocation_distanceContributesNothing() {
        let v = venue(id: "v", type: .bar, latitude: 25.7650, longitude: -80.1950)
        let withoutLocation = ExperienceScorer.score(venue: v, context: TripContext(), userCoordinate: nil)
        let baseline = ExperienceScorer.score(venue: v, context: TripContext())

        XCTAssertEqual(withoutLocation, baseline, accuracy: 0.0001)
    }

    // MARK: - Missing optional data never crashes or produces NaN/Infinity

    func test_venueWithNoOptionalSignalsAtAll_stillProducesFiniteScore() {
        let bareVenue = venue(id: "bare", type: .bar) // no slug, no events, no tags, 0,0 coordinate
        let score = ExperienceScorer.score(venue: bareVenue, context: TripContext())

        XCTAssertFalse(score.isNaN)
        XCTAssertFalse(score.isInfinite)
    }
}
