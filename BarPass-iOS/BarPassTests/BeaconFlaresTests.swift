import AVFoundation
import UIKit
import XCTest
@testable import BarPass_app

/// What can be proven without a torch: the pattern sanitizer, the
/// thermal/battery decision table, and the brightness bookkeeping.
///
/// What cannot, and is NOT asserted here — that the LED physically lights,
/// that `setTorchModeOn(level:)` produces the requested brightness, that iOS
/// honours a level of 1.0 without cutting it on its own, or that the pulse
/// keeps time under load. The simulator has no torch: `AVCaptureDevice`
/// resolves to nothing, so every torch call is a silent no-op. Those need a
/// real phone, which is exactly why the logic that *decides* was pulled out
/// into `FlarePolicy` — pure, and testable here.
final class BeaconFlaresTests: XCTestCase {

    // MARK: - Pattern sanitizing

    /// The 180ms floor is a seizure limit, not a hardware one. This is the
    /// assertion that has to survive anyone "optimizing" the constant: no
    /// input, however aggressive, may produce more than 3 flashes per second
    /// at a stranger in a dark room.
    func test_noPatternCanFlashFasterThanThreePerSecond() {
        for raw in [[1, 1], [10, 10, 10, 10], [50, 20, 50, 20, 50, 20], [179, 179]] {
            let pattern = FlarePattern(millisecondsAlternatingFromOn: raw)
            let onCount = Double(pattern.steps.filter(\.isOn).count)
            let flashesPerSecond = onCount * 1000.0 / Double(pattern.cycleMilliseconds)
            XCTAssertLessThan(flashesPerSecond, 3.0,
                "\(raw) produced \(flashesPerSecond) flashes/sec — above the photosensitivity threshold")
        }
    }

    func test_clampedPattern_reportsThatItWasClamped() {
        let pattern = FlarePattern(millisecondsAlternatingFromOn: [40, 40])
        XCTAssertTrue(pattern.wasClamped, "A silently rewritten pattern is a lie to the caller")
        XCTAssertEqual(pattern.steps.map(\.milliseconds), [180, 180])
    }

    func test_patternWithinLimits_isNotReportedAsClamped() {
        let pattern = FlarePattern(millisecondsAlternatingFromOn: [400, 700])
        XCTAssertFalse(pattern.wasClamped)
        XCTAssertEqual(pattern.steps, [.init(isOn: true, milliseconds: 400), .init(isOn: false, milliseconds: 700)])
        XCTAssertEqual(pattern.cycleMilliseconds, 1100)
    }

    /// An odd-length sequence ends on ON, which would fuse into a solid beam
    /// when the cycle repeats — a steady torch, not a beacon, at full drain.
    func test_oddLengthPattern_getsATrailingOff() {
        let pattern = FlarePattern(millisecondsAlternatingFromOn: [300, 300, 300])
        XCTAssertEqual(pattern.steps.count, 4)
        XCTAssertEqual(pattern.steps.last?.isOn, false)
        XCTAssertTrue(pattern.wasClamped)
    }

    func test_emptyOrNonPositiveInput_fallsBackToSteady_andSaysSo() {
        for raw in [[], [0], [-5, -5]] {
            let pattern = FlarePattern(millisecondsAlternatingFromOn: raw)
            XCTAssertFalse(pattern.steps.isEmpty, "\(raw) must never yield a zero-step pattern")
            XCTAssertTrue(pattern.wasClamped)
        }
    }

    func test_stepsAlwaysAlternateStartingOn() {
        let pattern = FlarePattern(millisecondsAlternatingFromOn: Array(repeating: 200, count: 8))
        XCTAssertEqual(pattern.steps.map(\.isOn), [true, false, true, false, true, false, true, false])
    }

    func test_stepCountIsCapped() {
        let pattern = FlarePattern(millisecondsAlternatingFromOn: Array(repeating: 200, count: 200))
        XCTAssertLessThanOrEqual(pattern.steps.count, FlarePattern.maximumSteps)
        XCTAssertTrue(pattern.wasClamped)
    }

    func test_dutyCycle_isTheLitFractionOfTheCycle() {
        let pattern = FlarePattern(millisecondsAlternatingFromOn: [250, 750])
        XCTAssertEqual(pattern.dutyCycle, 0.25, accuracy: 0.0001)
    }

    // MARK: - Mitigation decision table

    func test_healthyPhone_isNotMitigated() {
        XCTAssertEqual(FlarePolicy.mitigation(thermal: .nominal, battery: .known(0.9)), .none)
        XCTAssertEqual(FlarePolicy.mitigation(thermal: .fair, battery: .known(0.5)), .none)
    }

    /// We step down at `.serious` and cut at `.critical` rather than waiting
    /// for iOS to kill the torch itself — a beacon that dies with no
    /// explanation reads as a broken app at the worst possible moment.
    func test_thermalSerious_reduces_andCritical_goesMinimal() {
        XCTAssertEqual(FlarePolicy.mitigation(thermal: .serious, battery: .known(0.9)),
                       .reduce(.overheating(.serious)))
        XCTAssertEqual(FlarePolicy.mitigation(thermal: .critical, battery: .known(0.9)),
                       .minimal(.overheating(.critical)))
    }

    func test_lowBattery_killsTheTorchButKeepsTheScreen() {
        let mitigation = FlarePolicy.mitigation(thermal: .nominal, battery: .known(0.14))
        XCTAssertEqual(mitigation, .torchOff(.batteryLow(0.14)))
        XCTAssertEqual(FlarePolicy.screenStatus(mitigation), .boosted(FlarePolicy.fullScreen),
                       "The screen is the last beacon left; it must stay lit")
    }

    func test_criticalBattery_goesMinimal() {
        XCTAssertEqual(FlarePolicy.mitigation(thermal: .nominal, battery: .known(0.04)),
                       .minimal(.batteryCritical(0.04)))
    }

    /// iOS reports -1 until battery monitoring warms up. Treating that as 0%
    /// would shut the beacon down on a full phone; the honest move is to not
    /// mitigate on something we do not know.
    func test_unknownBattery_doesNotInventAShutdown() {
        XCTAssertEqual(FlarePolicy.mitigation(thermal: .nominal, battery: .unknown), .none)
        XCTAssertEqual(FlarePolicy.mitigation(thermal: .serious, battery: .unknown),
                       .reduce(.overheating(.serious)), "An unknown battery must not mask a known thermal state")
    }

    func test_worstSignalWins_regardlessOfWhichOneItIs() {
        // Thermal is worse than the battery here.
        XCTAssertEqual(FlarePolicy.mitigation(thermal: .critical, battery: .known(0.14)),
                       .minimal(.overheating(.critical)))
        // …and here the battery is worse than the thermal state.
        XCTAssertEqual(FlarePolicy.mitigation(thermal: .serious, battery: .known(0.03)),
                       .minimal(.batteryCritical(0.03)))
    }

    // MARK: - Status derivation

    /// A device with no torch is not a failure: the screen alone is still a
    /// beacon, and the reason has to be distinguishable from every other off.
    func test_missingHardware_overridesAHealthyMitigation() {
        let torch = FlarePolicy.torchStatus(.none, hardware: .noTorchHardware)
        XCTAssertEqual(torch, .off(because: .noTorchHardware))
        XCTAssertEqual(FlarePolicy.screenStatus(.none), .boosted(FlarePolicy.fullScreen))
    }

    func test_eachHardwareLimitKeepsItsOwnIdentity() {
        let limits: [FlareLimit] = [.noTorchHardware, .cameraBusy, .torchUnavailableUnknownReason]
        let statuses = limits.map { FlarePolicy.torchStatus(.none, hardware: $0) }
        XCTAssertEqual(Set(statuses.map { String(describing: $0) }).count, 3,
                       "Two hardware limits collapsed into the same state")
        for (limit, status) in zip(limits, statuses) {
            XCTAssertEqual(status, .off(because: limit), "\(limit) was collapsed into another state")
        }
    }

    func test_reduce_dimsTheTorchButDoesNotExtinguishIt() {
        let torch = FlarePolicy.torchStatus(.reduce(.overheating(.serious)), hardware: nil)
        XCTAssertEqual(torch, .dimmed(level: FlarePolicy.reducedTorchLevel, because: .overheating(.serious)))
        XCTAssertLessThan(FlarePolicy.reducedTorchLevel, AVCaptureDevice.maxAvailableTorchLevel)
    }

    func test_minimal_dimsTheScreenToo() {
        let screen = FlarePolicy.screenStatus(.minimal(.batteryCritical(0.03)))
        XCTAssertEqual(screen, .held(FlarePolicy.reducedScreen, because: .batteryCritical(0.03)))
        XCTAssertLessThan(FlarePolicy.reducedScreen, FlarePolicy.fullScreen)
    }

    func test_policyThresholdsAreOrdered() {
        XCTAssertGreaterThan(FlarePolicy.torchBatteryFloor, FlarePolicy.screenBatteryFloor,
                             "The torch must be sacrificed before the screen is")
        XCTAssertGreaterThan(FlarePolicy.maxSessionSeconds, 0)
        XCTAssertLessThanOrEqual(FlarePolicy.maxSessionSeconds, 900,
                                 "A cap long enough to drain a lost person's phone is not a cap")
    }

    // MARK: - Brightness bookkeeping

    /// The bug this guards: `start()` called twice would capture 1.0 the
    /// second time and "restore" the user to a screen pinned at maximum for
    /// the rest of the night.
    @MainActor
    func test_captureNeverOverwritesTheSavedValue() throws {
        BrightnessVault.restore()
        let original = UIScreen.main.brightness
        defer { UIScreen.main.brightness = original }

        UIScreen.main.brightness = 0.5
        try XCTSkipUnless(abs(UIScreen.main.brightness - 0.5) < 0.02,
                          "This runner does not accept brightness writes; nothing to prove here")
        BrightnessVault.capture()
        BrightnessVault.apply(1.0)
        BrightnessVault.capture() // a second start() must not re-capture 1.0

        let restored = try XCTUnwrap(BrightnessVault.restore())
        XCTAssertEqual(restored, 0.5, accuracy: 0.02)
        XCTAssertFalse(BrightnessVault.holdsValue, "restore() must clear the vault")
    }

    @MainActor
    func test_restoreOnAnEmptyVaultIsANoOp() {
        BrightnessVault.restore()
        XCTAssertNil(BrightnessVault.restore())
        XCTAssertFalse(BrightnessVault.holdsValue)
    }

    // MARK: - Session lifecycle

    /// Double start, single stop. If `start()` took a second hold, the
    /// counter would never reach zero and the brightness would never come
    /// back — the failure mode the whole service is built around.
    @MainActor
    func test_doubleStart_singleStop_fullyReleasesTheHardware() {
        let original = UIScreen.main.brightness
        defer { UIScreen.main.brightness = original }
        BrightnessVault.restore()
        UIApplication.shared.isIdleTimerDisabled = false

        let flares = BeaconFlares()
        flares.start(pattern: .steady)
        flares.start(pattern: .steady)
        flares.stop()

        XCTAssertEqual(flares.state, .idle)
        XCTAssertFalse(BrightnessVault.holdsValue,
                       "stop() left the vault held — the user stays at max brightness")
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled,
                       "stop() left the idle timer disabled; the screen will never lock")
    }

    /// The simulator (and any iPad) has no torch, so this is the honest
    /// degradation path running for real, not a mock of it.
    @MainActor
    func test_onADeviceWithNoTorch_theScreenStillRunsAsTheBeacon() throws {
        try XCTSkipUnless(AVCaptureDevice.default(for: .video)?.hasTorch != true,
                          "This device has a torch; the no-hardware path cannot be exercised here")
        BrightnessVault.restore()
        let flares = BeaconFlares()
        flares.start(pattern: .steady)
        defer { flares.stop() }

        guard case .active(let torch, let screen, _, let endsAt) = flares.state else {
            return XCTFail("start() left the beacon inactive: \(flares.state)")
        }
        XCTAssertEqual(torch, .off(because: .noTorchHardware))
        XCTAssertEqual(screen, .boosted(FlarePolicy.fullScreen))
        XCTAssertGreaterThan(endsAt.timeIntervalSinceNow, 0)
        XCTAssertLessThanOrEqual(endsAt.timeIntervalSinceNow, FlarePolicy.maxSessionSeconds)
    }

    @MainActor
    func test_renewPushesTheDeadlineForward() throws {
        BrightnessVault.restore()
        let flares = BeaconFlares()
        flares.start(pattern: .steady)
        defer { flares.stop() }
        guard case .active(_, _, _, let first) = flares.state else {
            return XCTFail("start() left the beacon inactive: \(flares.state)")
        }

        flares.renew()
        guard case .active(_, _, _, let second) = flares.state else {
            return XCTFail("renew() left the beacon inactive: \(flares.state)")
        }
        XCTAssertGreaterThanOrEqual(second, first)
    }
}
