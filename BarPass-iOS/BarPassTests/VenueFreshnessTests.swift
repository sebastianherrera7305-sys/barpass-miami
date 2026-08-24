import XCTest
@testable import BarPass_app

/// Runtime verification for Fase 1 (venue data freshness). Hits the real
/// Supabase `venues` REST endpoint — the whole point is proving the actor's
/// cache/force-refresh behavior against real network timing, not a mock that
/// can't distinguish "returned instantly from memory" from "made a real HTTP
/// round trip."
///
/// A third scenario (TTL actually expiring and triggering an automatic
/// re-fetch) was verified manually with `freshnessWindow` temporarily
/// shortened to 8s — confirmed via two real `fetchVenueRows()` calls 9s
/// apart. Not kept as a permanent test here: at the real 10-minute window,
/// that scenario would make every test run take 10+ minutes for no benefit
/// over the manual verification already done.
final class VenueFreshnessTests: XCTestCase {

    /// First call after a fresh instance must hit the network (nothing
    /// cached yet); an immediate second call must be a cache hit — proven by
    /// wall-clock time, not by inspecting private state.
    func test_firstCall_fetchesReal_secondCall_isCacheHit() async throws {
        let repo = SupabaseVenueRepository()

        let first = try await repo.getVenues()
        XCTAssertFalse(first.isEmpty, "First call should return real venues from Supabase")

        let t1 = Date()
        let second = try await repo.getVenues()
        let secondDuration = Date().timeIntervalSince(t1)
        XCTAssertEqual(first.count, second.count)

        // A real HTTPS round trip to Supabase REST is never sub-50ms; an
        // in-memory cache hit always is.
        XCTAssertLessThan(secondDuration, 0.05,
            "Second call within the freshness window returned in \(secondDuration)s — too slow to be a cache hit")
    }

    /// forceRefresh (what pull-to-refresh calls) must always hit the
    /// network, even immediately after a call that was itself fresh.
    func test_forceRefresh_alwaysFetchesReal_evenWithinWindow() async throws {
        let repo = SupabaseVenueRepository()
        _ = try await repo.getVenues() // warm the cache

        let t0 = Date()
        let refreshed = try await repo.refresh()
        let duration = Date().timeIntervalSince(t0)
        XCTAssertFalse(refreshed.isEmpty)

        XCTAssertGreaterThan(duration, 0.05,
            "refresh() returned in \(duration)s — too fast to be a real network fetch, suggests it served the cache instead of forcing one")
    }
}
