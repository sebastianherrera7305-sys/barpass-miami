import XCTest
@testable import BarPass_app

/// `PriceTier` (ADR-014) is the single normalization point for Supabase's
/// `price_tier` column — every edge case below must resolve to a defined
/// case, never crash, and never silently misrepresent an out-of-range value
/// as a valid tier.
final class PriceTierTests: XCTestCase {

    func test_validTiers_mapDirectly() {
        XCTAssertEqual(PriceTier(rawSupabaseValue: 1), .tier1)
        XCTAssertEqual(PriceTier(rawSupabaseValue: 2), .tier2)
        XCTAssertEqual(PriceTier(rawSupabaseValue: 3), .tier3)
        XCTAssertEqual(PriceTier(rawSupabaseValue: 4), .tier4)
    }

    func test_nil_mapsToUnknown() {
        XCTAssertEqual(PriceTier(rawSupabaseValue: nil), .unknown)
    }

    func test_zero_mapsToUnknown() {
        // 0 is not a valid Google Places price level (1-4) — must not be
        // mistaken for "free"/tier0.
        XCTAssertEqual(PriceTier(rawSupabaseValue: 0), .unknown)
    }

    func test_negative_mapsToUnknown() {
        XCTAssertEqual(PriceTier(rawSupabaseValue: -1), .unknown)
    }

    func test_aboveRange_mapsToUnknown() {
        XCTAssertEqual(PriceTier(rawSupabaseValue: 5), .unknown)
        XCTAssertEqual(PriceTier(rawSupabaseValue: 100), .unknown)
    }

    func test_symbol_rendersDollarSignsForValidTiers() {
        XCTAssertEqual(PriceTier.tier1.symbol, "$")
        XCTAssertEqual(PriceTier.tier2.symbol, "$$")
        XCTAssertEqual(PriceTier.tier3.symbol, "$$$")
        XCTAssertEqual(PriceTier.tier4.symbol, "$$$$")
    }

    func test_symbol_nilForUnknown() {
        // The UI layer is responsible for falling back to a localized
        // "N/A"/"N/D" string here — the model/formatter never fabricates one.
        XCTAssertNil(PriceTier.unknown.symbol)
    }
}
