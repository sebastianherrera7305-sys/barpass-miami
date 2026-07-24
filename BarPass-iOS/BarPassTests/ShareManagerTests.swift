import XCTest
@testable import BarPass_app

/// Covers ShareManager's content-building logic — text and URL construction
/// per type — without needing a live UI (the actual UIActivityViewController
/// presentation is verified separately in the simulator, per the S2 report).
@MainActor
final class ShareManagerTests: XCTestCase {

    // MARK: - Venue: the URL bug this whole pass exists to fix

    func test_shareVenue_withSlug_usesRealWebURL_notID() {
        var venue = BarPassVenue.preview
        // A slug unrelated to id (not even a substring of it, unlike
        // .preview's own fixture) — this is the case that actually proves
        // the old `/venues/{id}` bug can't recur: if ShareManager fell back
        // to id anywhere, this exact URL assertion would fail.
        venue.slug = "club-99-downtown"
        let content = ShareManager.shareVenue(venue)
        XCTAssertEqual(content.url?.absoluteString, "https://barpass.app/venues/club-99-downtown")
    }

    func test_shareVenue_withoutSlug_fallsBackToCustomScheme_neverBrokenWebURL() {
        var venue = BarPassVenue.preview
        venue.slug = nil // simulates a venue decoded from a pre-slug cache
        let content = ShareManager.shareVenue(venue)
        XCTAssertEqual(content.url?.absoluteString, "barpass://venue/\(venue.id)")
    }

    func test_shareVenue_text_includesNameAndNeighborhood() {
        let venue = BarPassVenue.preview
        let content = ShareManager.shareVenue(venue)
        XCTAssertTrue(content.text.contains(venue.name))
        XCTAssertTrue(content.text.contains(venue.neighborhood))
    }

    func test_shareVenue_producesCardImage() {
        let content = ShareManager.shareVenue(.preview)
        XCTAssertNotNil(content.cardImage)
    }

    // MARK: - Trip

    func test_shareTrip_url_isWebLandingAndMatchesDeepLinkRouterShape() {
        let trip = Trip(creatorId: "u1", title: "Miami Weekend", destinationCity: "Miami",
                         startDate: Date(), endDate: Date().addingTimeInterval(86400))
        let content = ShareManager.shareTrip(trip)
        // S3: shares the real web landing (works for non-app-users too), not
        // the scheme-only link — but it must still be exactly what
        // DeepLinkRouter parses, so tapping it from an installed app works.
        XCTAssertEqual(content.url?.absoluteString, "https://barpass.app/trip/\(trip.id)")
        XCTAssertEqual(DeepLinkRouter.parse(content.url!), .trip(id: trip.id))
    }

    func test_shareTrip_text_includesTitleAndInviteCode() {
        var trip = Trip(creatorId: "u1", title: "Miami Weekend", destinationCity: "Miami",
                         startDate: Date(), endDate: Date().addingTimeInterval(86400))
        trip.inviteCode = "JOIN99"
        let content = ShareManager.shareTrip(trip)
        XCTAssertTrue(content.text.contains("Miami Weekend"))
        XCTAssertTrue(content.text.contains("JOIN99"))
    }

    func test_shareTrip_producesCardImage() {
        let trip = Trip(creatorId: "u1", title: "Miami Weekend", destinationCity: "Miami",
                         startDate: Date(), endDate: Date().addingTimeInterval(86400))
        let content = ShareManager.shareTrip(trip)
        XCTAssertNotNil(content.cardImage)
    }

    // MARK: - Pass / Reservation / Ticket — no URL, real text (was hardcoded, unlocalized)

    func test_sharePass_text_includesVenueAndCode() {
        let pass = SkipLinePass.new(venueId: "liv", venueName: "LIV Miami", quantity: 2, amount: 45, payMethod: "Apple Pay")
        let content = ShareManager.sharePass(pass)
        XCTAssertTrue(content.text.contains("LIV Miami"))
        XCTAssertTrue(content.text.contains(pass.passCode))
        XCTAssertNil(content.url)
    }

    func test_shareReservation_text_includesVenueAndCode() {
        let reservation = TableReservation.new(
            venueId: "liv", venueName: "LIV Miami", package: TablePackage.all[0],
            guestCount: 4, timeSlot: "11:00 PM", slotDate: Date(), payMethod: "Apple Pay"
        )
        let content = ShareManager.shareReservation(reservation)
        XCTAssertTrue(content.text.contains("LIV Miami"))
        XCTAssertTrue(content.text.contains(reservation.confirmCode))
        XCTAssertNil(content.url)
    }

    func test_shareTicket_text_includesEventAndCode() {
        let ticket = EventTicket.new(eventName: "New Year's Eve", venueName: "LIV Miami", venueId: "liv",
                                      eventDate: Date(), quantity: 2, package: "GA", amount: 100, payMethod: "Apple Pay")
        let content = ShareManager.shareTicket(ticket)
        XCTAssertTrue(content.text.contains("New Year's Eve"))
        XCTAssertTrue(content.text.contains(ticket.ticketCode))
        XCTAssertNil(content.url)
    }

    // MARK: - Referral (infrastructure only)

    func test_shareReferral_includesCodeAndProducesCard() {
        let content = ShareManager.shareReferral(inviteCode: "SEB123")
        XCTAssertTrue(content.text.contains("SEB123"))
        XCTAssertNotNil(content.url)
        XCTAssertNotNil(content.cardImage)
    }
}
