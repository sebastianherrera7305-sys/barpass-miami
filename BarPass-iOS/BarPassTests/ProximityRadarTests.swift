import XCTest
import simd
@testable import BarPass_app

/// This is a safety feature, so the failure that matters is not "the arrow is a
/// bit off" — it is "the arrow confidently points at nothing and somebody walks
/// the wrong way through a crowd". Every test here is about what the machine
/// says when it does NOT know. It all runs against `ProximityRadarCore`, which
/// holds the whole state machine as a value: no NearbyInteraction, no UWB radio,
/// no second phone. The transport seam lives in `ProximityRadarChannelTests`.
final class ProximityRadarTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    /// Phone-frame unit vectors: +y out of the top edge, +x right, +z out
    /// through the screen at the person holding it.
    private let ahead = SIMD3<Double>(0, 1, 0)
    private let toTheRight = SIMD3<Double>(1, 0, 0)
    private let behind = SIMD3<Double>(0, -1, 0)
    private let throughTheScreen = SIMD3<Double>(0, 0, 1)
    private func sample(_ meters: Double?, _ direction: SIMD3<Double>? = nil) -> ProximitySample {
        ProximitySample(distanceMeters: meters, direction: direction)
    }

    /// Both phones capable, both in the session, nothing measured yet.
    private func live(_ tuning: ProximityTuning = .default) -> ProximityRadarCore {
        var core = ProximityRadarCore(capability: .distanceAndDirection, tuning: tuning)
        core.start()
        core.adoptPeerCapability(.distanceAndDirection)
        core.peerJoined()
        return core
    }

    // MARK: - Hardware that cannot do this

    func test_phoneWithoutUWB_saysSoAndNoReadingCanTalkItRound() {
        var core = ProximityRadarCore(capability: .cannotRange)
        core.start()
        XCTAssertEqual(core.state, .unsupported)
        XCTAssertTrue(core.state.shouldFallBackToBeacon)

        core.ingest(sample(3, ahead), now: at(0))
        XCTAssertEqual(core.state, .unsupported, "a phone with no radio cannot produce a reading, so one must change nothing")
    }

    func test_capablePhone_startsByWaitingForTheOtherPerson() {
        var core = ProximityRadarCore(capability: .distanceAndDirection)
        core.start()
        XCTAssertEqual(core.state, .waitingForPeer)
        XCTAssertFalse(core.state.shouldFallBackToBeacon)
    }

    func test_peerWithoutUWB_isADifferentSentenceFromOurOwnPhoneLacking() {
        var core = ProximityRadarCore(capability: .distanceAndDirection)
        core.start()
        core.adoptPeerCapability(.cannotRange)
        XCTAssertEqual(core.state, .peerCannotRange)
        XCTAssertNotEqual(core.state.messageKey, ProximityRadarState.unsupported.messageKey)
        XCTAssertTrue(core.state.shouldFallBackToBeacon)
    }

    func test_peerThatCannotPoint_neverProducesAnArrowEvenWithAVector() {
        var core = ProximityRadarCore(capability: .distanceAndDirection)
        core.start()
        // Direction needs both radios. One SE in the pair and nobody points.
        core.adoptPeerCapability(.distanceOnly)
        core.peerJoined()
        core.ingest(sample(6, toTheRight), now: at(0))

        XCTAssertNil(core.state.heading)
        guard case .distanceOnly = core.state else {
            return XCTFail("expected distance only, got \(core.state)")
        }
    }

    // MARK: - Pointing

    func test_azimuthCoversTheWholeCircle_soBehindIsNotDrawnAsAhead() throws {
        for (vector, expected) in [(ahead, 0.0), (toTheRight, Double.pi / 2), (behind, Double.pi)] {
            var core = live()
            core.ingest(sample(4, vector), now: at(0))
            let heading = try XCTUnwrap(core.state.heading, "expected an arrow for \(vector)")
            // abs(): ±π are the same bearing, and the sign there is arbitrary.
            XCTAssertEqual(abs(heading.azimuth), expected, accuracy: 0.001)
        }
    }

    func test_phoneHeldFaceOn_asksTheUserToFixItInsteadOfGuessingAnAngle() {
        var core = live()
        core.ingest(sample(4, throughTheScreen), now: at(0))

        XCTAssertNil(core.state.heading, "the in-plane angle is noise in this posture")
        guard case .holdPhoneFlat(let meters) = core.state else {
            return XCTFail("expected holdPhoneFlat, got \(core.state)")
        }
        XCTAssertEqual(try XCTUnwrap(meters), 4, accuracy: 0.001, "the distance is still good")
    }

    func test_arrowGoesUnconfirmedAndThenDisappears_ratherThanFreezing() {
        var core = live()
        core.ingest(sample(4, toTheRight), now: at(0))
        XCTAssertEqual(core.state.heading?.isConfirmed, true)

        // Past the confirm window, inside the grace: still drawn, but flagged
        // so the UI dims it — a person turning in place invalidates it fast.
        core.tick(now: at(0.4))
        XCTAssertEqual(core.state.heading?.isConfirmed, false)

        // Distance keeps arriving, direction does not. The arrow goes away.
        core.ingest(sample(4), now: at(1.0))
        XCTAssertNil(core.state.heading)
        guard case .distanceOnly = core.state else {
            return XCTFail("expected distance only, got \(core.state)")
        }
    }

    // MARK: - Losing them

    func test_silenceBecomesSignalLost_datedToTheLastRealReading() throws {
        var core = live()
        core.ingest(sample(7), now: at(0))

        core.tick(now: at(1.9))
        guard case .distanceOnly = core.state else {
            return XCTFail("1.9s is inside the window; expected distance, got \(core.state)")
        }

        core.tick(now: at(2.1))
        guard case .signalLost(let lastMeters, let when) = core.state else {
            return XCTFail("expected signalLost, got \(core.state)")
        }
        XCTAssertEqual(try XCTUnwrap(lastMeters), 7, accuracy: 0.001)
        XCTAssertEqual(when, at(0), "dated to when we actually measured, not to now")
        XCTAssertNil(core.state.meters, "the live distance is gone; the old one is only in the payload, labelled")
    }

    func test_smoothingDoesNotGlideAcrossAHoleItAlreadyReportedAsLost() throws {
        var core = live()
        core.ingest(sample(8), now: at(0))
        core.tick(now: at(3))
        guard case .signalLost = core.state else { return XCTFail("expected signalLost, got \(core.state)") }

        core.ingest(sample(2), now: at(3.1))
        XCTAssertEqual(try XCTUnwrap(core.state.meters), 2, accuracy: 0.0001,
                       "the filter must restart on the new reading, not animate 8m→2m through a gap nobody measured")
    }

    func test_smoothingAbsorbsJitterButStillFollowsRealMovement() throws {
        var core = live()
        var t = 0.0
        // 2 seconds of standing still at 5m with the ±0.25m jitter UWB really has.
        for step in 0..<20 {
            core.ingest(sample(step.isMultiple(of: 2) ? 5.25 : 4.75), now: at(t))
            t += 0.1
        }
        XCTAssertEqual(try XCTUnwrap(core.state.meters), 5.0, accuracy: 0.15)

        // Then walk in from 5m to 2m and stop.
        for step in 1...20 {
            core.ingest(sample(5 - 3 * Double(step) / 20), now: at(t))
            t += 0.1
        }
        for _ in 0..<10 {
            core.ingest(sample(2.0), now: at(t))
            t += 0.1
        }
        XCTAssertEqual(try XCTUnwrap(core.state.meters), 2.0, accuracy: 0.2, "lag must not outlive the movement")
    }

    // MARK: - Arriving

    func test_atArmsLengthTheArrowStops_andHysteresisKeepsItFromFlapping() throws {
        var core = live()
        core.ingest(sample(1.4, toTheRight), now: at(0))
        guard case .arrived(let meters) = core.state else {
            return XCTFail("expected arrived, got \(core.state)")
        }
        XCTAssertEqual(meters, 1.4, accuracy: 0.001)
        XCTAssertNil(core.state.heading, "between two people standing up, the arrow is their own swaying")
        XCTAssertTrue(core.state.shouldFallBackToBeacon, "stop pointing, show the colour")

        // Drifting to 2m must not flip the screen back to an arrow.
        core.ingest(sample(2.0, toTheRight), now: at(0.1))
        guard case .arrived = core.state else {
            return XCTFail("hysteresis should hold through 2m, got \(core.state)")
        }

        // Genuinely walking off does bring it back.
        for step in 2...12 { core.ingest(sample(5, toTheRight), now: at(Double(step) * 0.1)) }
        XCTAssertNotNil(core.state.heading)
    }

    // MARK: - Leaving, pausing, breaking

    func test_backgroundingSaysPaused_andNeverKeepsTheLastArrowOnScreen() {
        var core = live()
        core.ingest(sample(3, toTheRight), now: at(0))
        XCTAssertNotNil(core.state.heading)

        core.suspend()
        XCTAssertEqual(core.state, .paused)
        XCTAssertNil(core.state.heading)
        XCTAssertNil(core.state.meters)

        core.ingest(sample(3, toTheRight), now: at(0.1))
        XCTAssertEqual(core.state, .paused, "NearbyInteraction is stopped; nothing can be arriving")

        core.resume()
        XCTAssertEqual(core.state, .acquiring, "a reading earns a number, coming back to the foreground does not")
    }

    func test_resumeRestartsTheFilterInsteadOfGlidingAcrossTheGap() throws {
        var core = live()
        core.ingest(sample(3), now: at(0))
        core.suspend()
        core.resume()
        core.ingest(sample(9), now: at(30))
        XCTAssertEqual(try XCTUnwrap(core.state.meters), 9, accuracy: 0.0001)
    }

    func test_peerLeaving_survivesReadingsButNotTheirComingBack() {
        var core = live()
        core.ingest(sample(3, toTheRight), now: at(0))
        core.peerLeft()
        XCTAssertEqual(core.state, .peerLeft)

        core.ingest(sample(3, toTheRight), now: at(0.1))
        core.tick(now: at(0.2))
        XCTAssertEqual(core.state, .peerLeft, "they are gone; a stray reading does not bring them back")

        // A new token, though, IS them reopening the app.
        core.peerJoined()
        XCTAssertEqual(core.state, .acquiring)
        core.ingest(sample(3, toTheRight), now: at(5))
        XCTAssertNotNil(core.state.heading)
    }

    func test_deadTransportIsFatalBeforeTheHandshakeAndHarmlessAfterIt() {
        var beforeHandshake = ProximityRadarCore(capability: .distanceAndDirection)
        beforeHandshake.start()
        beforeHandshake.channelFailed()
        XCTAssertEqual(beforeHandshake.state, .failed(.channelUnavailable))

        var ranging = live()
        ranging.ingest(sample(4), now: at(0))
        ranging.channelFailed()
        guard case .distanceOnly = ranging.state else {
            return XCTFail("UWB ranging is phone-to-phone and needs no server; a dead channel must not stop it, got \(ranging.state)")
        }
    }

    // MARK: - Trend (the honest replacement for "hotter / colder")

    func test_trendNeedsRealMovement_andAdmitsWhenItHasNone() throws {
        var core = live()
        core.ingest(sample(10), now: at(0))
        core.ingest(sample(9.9), now: at(0.5))
        guard case .distanceOnly(_, let initialTrend) = core.state else {
            return XCTFail("expected distance only, got \(core.state)")
        }
        XCTAssertEqual(initialTrend, .unknown, "10cm is inside the reading noise; calling it 'closer' would be invention")

        var t = 1.0
        for step in 0..<10 {
            core.ingest(sample(9.8 - 0.2 * Double(step)), now: at(t))
            t += 0.1
        }
        guard case .distanceOnly(_, let walkingTrend) = core.state else {
            return XCTFail("expected distance only, got \(core.state)")
        }
        XCTAssertEqual(walkingTrend, .closer)

        while t <= 7.0 {
            core.ingest(sample(8.0), now: at(t))
            t += 0.25
        }
        guard case .distanceOnly(_, let stoppedTrend) = core.state else {
            return XCTFail("expected distance only, got \(core.state)")
        }
        XCTAssertEqual(stoppedTrend, .steady)
    }

    // MARK: - No two different situations may share a sentence

    func test_everyDistinguishableStateHasItsOwnMessage() {
        let states: [ProximityRadarState] = [
            .idle, .unsupported, .permissionDenied, .waitingForPeer, .peerCannotRange, .acquiring,
            .distanceOnly(meters: 5, trend: .steady), .distanceOnly(meters: 5, trend: .closer),
            .distanceOnly(meters: 5, trend: .farther), .holdPhoneFlat(meters: 5), .arrived(meters: 1),
            .directed(meters: 5, heading: ProximityHeading(azimuth: 0, isConfirmed: true)),
            .directed(meters: 5, heading: ProximityHeading(azimuth: 0, isConfirmed: false)),
            .signalLost(lastMeters: 5, at: t0), .peerLeft, .paused,
            .failed(.channelUnavailable), .failed(.peerDeviceIncompatible)
        ]
        let keys = states.map(\.messageKey)
        XCTAssertEqual(Set(keys).count, keys.count, "two different situations are sharing one sentence: \(keys)")
    }
}
