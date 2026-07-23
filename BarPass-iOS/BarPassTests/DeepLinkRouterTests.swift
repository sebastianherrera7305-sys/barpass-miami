import XCTest
@testable import BarPass_app

/// Covers DeepLinkRouter.parse — the pure URL→route mapping the whole deep-link
/// feature rests on. No app or simulator needed.
final class DeepLinkRouterTests: XCTestCase {

    private func route(_ s: String) -> DeepLinkRoute? {
        DeepLinkRouter.parse(URL(string: s)!)
    }

    // MARK: Custom scheme — valid

    func test_customScheme_trip() {
        XCTAssertEqual(route("barpass://trip/abc123"), .trip(id: "abc123"))
    }
    func test_customScheme_venue() {
        XCTAssertEqual(route("barpass://venue/liv-miami"), .venue(id: "liv-miami"))
    }
    func test_customScheme_futureRoutes_parsed() {
        XCTAssertEqual(route("barpass://pass/p1"), .pass(id: "p1"))
        XCTAssertEqual(route("barpass://invite/JOIN99"), .invite(code: "JOIN99"))
        XCTAssertEqual(route("barpass://profile/u1"), .profile(id: "u1"))
    }
    func test_scheme_and_type_areCaseInsensitive() {
        XCTAssertEqual(route("BARPASS://Trip/abc"), .trip(id: "abc"))
    }

    // MARK: Universal / web links — valid

    func test_https_canonicalDomain_trip() {
        XCTAssertEqual(route("https://barpass.app/trip/abc123"), .trip(id: "abc123"))
    }
    func test_https_vercelDomain_venue() {
        XCTAssertEqual(route("https://barpass-v2.vercel.app/venue/v1"), .venue(id: "v1"))
    }

    // MARK: Invalid — must return nil, never crash

    func test_emptyValue_isNil() {
        XCTAssertNil(route("barpass://trip/"))
    }
    func test_missingValue_isNil() {
        XCTAssertNil(route("barpass://trip"))
    }
    func test_unknownType_isNil() {
        XCTAssertNil(route("barpass://unknown/test"))
    }
    func test_https_singleSegment_isNil() {
        XCTAssertNil(route("https://barpass.app/trip"))
    }
    func test_unsupportedScheme_isNil() {
        XCTAssertNil(route("ftp://barpass.app/trip/abc"))
    }
    func test_bareScheme_isNil() {
        XCTAssertNil(route("barpass://"))
    }
}
