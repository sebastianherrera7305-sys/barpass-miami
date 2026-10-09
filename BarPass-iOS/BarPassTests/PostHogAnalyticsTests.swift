import XCTest
@testable import BarPass_app

/// Covers the pure event→payload mapping. The actual network layer is a
/// one-line URLSession POST that we don't need to mock — if the mapper
/// is correct, the wire format is correct.
final class PostHogAnalyticsTests: XCTestCase {

    // MARK: - Event names

    func test_appOpened_mapsToSnakeCaseName_withColdStartFlag() {
        let m = PostHogEventMapper.map(.appOpened(coldStart: true, secondsSinceLastOpen: nil))
        XCTAssertEqual(m.name, "app_opened")
        XCTAssertEqual(m.properties["cold_start"] as? Bool, true)
        // Omitted when nil — don't send empty values.
        XCTAssertNil(m.properties["seconds_since_last_open"])
    }

    func test_appOpened_includesSecondsSinceLastOpen_whenProvided() {
        let m = PostHogEventMapper.map(.appOpened(coldStart: false, secondsSinceLastOpen: 42))
        XCTAssertEqual(m.properties["cold_start"] as? Bool, false)
        XCTAssertEqual(m.properties["seconds_since_last_open"] as? Int, 42)
    }

    func test_avatarSaved_distinguishesFirstTimeFromReedit() {
        XCTAssertEqual(
            PostHogEventMapper.map(.avatarSaved(isFirstTime: true)).properties["is_first_time"] as? Bool,
            true
        )
        XCTAssertEqual(
            PostHogEventMapper.map(.avatarSaved(isFirstTime: false)).properties["is_first_time"] as? Bool,
            false
        )
    }

    func test_venueCheckin_sendsVenueIdButNeverLatLng() {
        let m = PostHogEventMapper.map(.venueCheckin(venueId: "venue_abc", tripId: nil))
        XCTAssertEqual(m.name, "venue_checkin")
        XCTAssertEqual(m.properties["venue_id"] as? String, "venue_abc")
        XCTAssertEqual(m.properties["has_trip"] as? Bool, false)
        // Explicit audit — none of these may ever appear.
        XCTAssertNil(m.properties["lat"])
        XCTAssertNil(m.properties["lng"])
        XCTAssertNil(m.properties["latitude"])
        XCTAssertNil(m.properties["longitude"])
        XCTAssertNil(m.properties["accuracy"])
    }

    func test_venueCheckin_withTrip_includesHasTripTrue() {
        let m = PostHogEventMapper.map(.venueCheckin(venueId: "venue_abc", tripId: "trip_xyz"))
        XCTAssertEqual(m.properties["has_trip"] as? Bool, true)
        XCTAssertEqual(m.properties["trip_id"] as? String, "trip_xyz")
    }

    func test_tripCreatedDetailed_sendsMethodAndMemberCount() {
        let m = PostHogEventMapper.map(.tripCreatedDetailed(method: "ai", memberCount: 4))
        XCTAssertEqual(m.name, "trip_created")
        XCTAssertEqual(m.properties["method"] as? String, "ai")
        XCTAssertEqual(m.properties["member_count"] as? Int, 4)
    }

    func test_tripCompleted_omitsDurationWhenNil() {
        let m = PostHogEventMapper.map(.tripCompleted(tripId: "t1", stopCount: 3, durationHours: nil))
        XCTAssertEqual(m.properties["trip_id"] as? String, "t1")
        XCTAssertEqual(m.properties["stop_count"] as? Int, 3)
        XCTAssertNil(m.properties["duration_hours"])
    }

    func test_tripCompleted_roundsDurationToOneDecimal() {
        let m = PostHogEventMapper.map(.tripCompleted(tripId: "t1", stopCount: 2, durationHours: 3.47))
        XCTAssertEqual(m.properties["duration_hours"] as? Double, 3.5)
    }

    func test_friendProfileOpened_takesPrehashedId_doesNotHashHere() {
        // Caller is responsible for hashing — the mapper is the honest
        // single enforcement point for property shape, but the hash salt
        // lives on the device (PostHogIDHasher) and must be applied
        // BEFORE this call, not after.
        let m = PostHogEventMapper.map(.friendProfileOpened(friendIdHash: "h_abc123"))
        XCTAssertEqual(m.properties["friend_id_hash"] as? String, "h_abc123")
        // There should be nothing resembling a raw uuid in the payload.
        XCTAssertNil(m.properties["friend_id"])
        XCTAssertNil(m.properties["user_id"])
    }

    // MARK: - Payment events

    func test_paymentSuccess_convertsDollarsToCents() {
        let m = PostHogEventMapper.map(.paymentSuccess(method: "card", amount: 25.50))
        XCTAssertEqual(m.name, "payment_succeeded")
        XCTAssertEqual(m.properties["method"] as? String, "card")
        XCTAssertEqual(m.properties["amount_cents"] as? Int, 2550)
    }

    func test_buySkipLinePass_carriesVenueIdOnly() {
        let m = PostHogEventMapper.map(.buySkipLinePass(venue: "venue_123"))
        XCTAssertEqual(m.name, "skip_line_purchased")
        XCTAssertEqual(m.properties["venue_id"] as? String, "venue_123")
        XCTAssertEqual(m.properties.count, 1)
    }

    // MARK: - Privacy guarantees

    func test_deepLink_sendsSchemeAndHostOnly_neverPathOrQuery() {
        let url = URL(string: "barpass://trip/abc123?invite=XYZ")!
        let m = PostHogEventMapper.map(.deepLink(url))
        XCTAssertEqual(m.name, "deep_link_opened")
        XCTAssertEqual(m.properties["scheme"] as? String, "barpass")
        XCTAssertEqual(m.properties["host"] as? String, "trip")
        // Path and query must NOT leak — a /trip/abc123 contains a trip
        // id, and ?invite= contains the raw invite code.
        XCTAssertNil(m.properties["path"])
        XCTAssertNil(m.properties["query"])
        XCTAssertNil(m.properties["url"])
    }

    // MARK: - ID hashing

    func test_postHogIDHasher_isStableForTheSameInputOnOneInstall() {
        let a = PostHogIDHasher.hash("friend_uid_1")
        let b = PostHogIDHasher.hash("friend_uid_1")
        XCTAssertEqual(a, b)
    }

    func test_postHogIDHasher_producesDifferentOutputsForDifferentInputs() {
        let a = PostHogIDHasher.hash("friend_uid_1")
        let b = PostHogIDHasher.hash("friend_uid_2")
        XCTAssertNotEqual(a, b)
    }

    func test_postHogIDHasher_outputHasH_prefix_soItsClearlyNotARawId() {
        XCTAssertTrue(PostHogIDHasher.hash("anything").hasPrefix("h_"))
    }
}
