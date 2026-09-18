import Foundation
import simd

/// The whole state machine, as a value. No NearbyInteraction, no timers, no
/// isolation — you feed it readings and clock ticks and read `state` back.
///
/// It lives apart from `ProximityRadar` for one reason: every honesty rule in
/// this feature (never freeze an arrow, never glide a filter across a hole we
/// reported as lost, never promise direction the hardware cannot give) is
/// testable only if it can be exercised without two UWB phones in a room. See
/// `ProximityRadarTests`.
struct ProximityRadarCore: Sendable {
    let tuning: ProximityTuning
    private(set) var capability: ProximityCapability
    private(set) var state: ProximityRadarState = .idle

    private var smoothedMeters: Double?
    private var smoothedDirection: SIMD3<Double>?
    private var lastDistanceAt: Date?
    private var lastDirectionAt: Date?
    private var isArrived = false
    private var trend: ProximityTrend = .unknown
    private var trendAnchor: (meters: Double, at: Date)?
    private var hasPeer = false

    init(capability: ProximityCapability, tuning: ProximityTuning = .default) {
        self.capability = capability
        self.tuning = tuning
    }

    // MARK: - Lifecycle

    mutating func start() {
        resetReadings()
        hasPeer = false
        state = capability == .cannotRange ? .unsupported : .waitingForPeer
    }

    /// Direction needs both radios, so the pair's capability is the weaker one.
    /// Which side is missing it is a different sentence for the user, so the
    /// two are not collapsed into one "unsupported".
    mutating func adoptPeerCapability(_ peer: ProximityCapability) {
        capability = capability.reduced(with: peer)
        guard capability == .cannotRange else { return }
        state = peer == .cannotRange ? .peerCannotRange : .unsupported
    }

    mutating func peerJoined() {
        // A new token is evidence they reopened the app, and that is the one
        // blocked state it may undo. Missing hardware, a denied permission and
        // a real failure are not undone by the far side coming back.
        if state == .peerLeft { state = .waitingForPeer }
        guard !isBlocked else { return }
        hasPeer = true
        resetReadings()
        state = .acquiring
    }

    mutating func peerLeft() {
        hasPeer = false
        state = .peerLeft
    }

    mutating func peerCannotRange() {
        capability = .cannotRange
        state = .peerCannotRange
    }

    mutating func permissionDenied() { state = .permissionDenied }

    mutating func platformUnsupported() {
        capability = .cannotRange
        state = .unsupported
    }

    mutating func fail(_ failure: ProximityRadarFailure) { state = .failed(failure) }

    /// Once UWB ranging is up it is phone-to-phone and needs no server, so a
    /// dead transport is only fatal before the handshake lands. After it we
    /// keep ranging — and NearbyInteraction's own removal callback still tells
    /// us when they leave, so nothing is silently lost.
    mutating func channelFailed() {
        guard !hasPeer else { return }
        state = .failed(.channelUnavailable)
    }

    /// The app left the foreground. Apple does not allow phone-to-phone ranging
    /// in the background, so readings stop here — holding the last arrow on a
    /// screen the user is about to come back to is exactly the frozen lie this
    /// type exists to prevent.
    mutating func suspend() {
        guard !isBlocked else { return }
        resetReadings()
        state = .paused
    }

    mutating func resume() {
        guard state == .paused else { return }
        resetReadings()
        state = hasPeer ? .acquiring : .waitingForPeer
    }

    /// NearbyInteraction gave up on the peer. Keep `hasPeer` — the session is
    /// re-run — but say out loud that the signal is gone, dated to the last
    /// reading we actually took.
    mutating func signalTimedOut(now: Date) {
        guard !isBlocked else { return }
        state = .signalLost(lastMeters: smoothedMeters, at: lastReadingAt ?? now)
    }

    mutating func stop() {
        resetReadings()
        hasPeer = false
        state = .idle
    }

    // MARK: - Readings

    mutating func ingest(_ sample: ProximitySample, now: Date) {
        guard !isBlocked else { return }
        hasPeer = true
        ingestDistance(sample.distanceMeters, now: now)
        ingestDirection(sample.direction, now: now)
        recompute(now: now)
    }

    /// Drives the staleness transitions when no reading arrives at all.
    mutating func tick(now: Date) {
        guard !isBlocked else { return }
        recompute(now: now)
    }

    private mutating func ingestDistance(_ raw: Double?, now: Date) {
        guard let raw, raw.isFinite, raw >= 0 else { return }
        let gap = elapsed(since: lastDistanceAt, now: now)
        if let current = smoothedMeters, gap <= tuning.staleAfter {
            // Time-based alpha: the filter is defined in seconds, so an update
            // rate change cannot silently change how laggy it is.
            let alpha = 1 - exp(-gap / tuning.smoothingTau)
            smoothedMeters = current + alpha * (raw - current)
        } else {
            // First reading, or the first one after a hole we already reported
            // as lost. Gliding the filter across that hole would draw a
            // continuity nobody measured.
            smoothedMeters = raw
            trendAnchor = (raw, now)
            trend = .unknown
        }
        lastDistanceAt = now
        updateTrend(now: now)
        updateArrivedLatch()
    }

    private mutating func ingestDirection(_ raw: SIMD3<Double>?, now: Date) {
        guard capability == .distanceAndDirection,
              let raw, let unit = Self.unit(raw) else { return }
        let gap = elapsed(since: lastDirectionAt, now: now)
        if let current = smoothedDirection, gap <= tuning.directionGrace {
            // Smoothed as a VECTOR, never as an angle: averaging degrees wraps
            // at ±180, so a peer wandering across "directly behind" would
            // average out to "directly ahead".
            let alpha = 1 - exp(-gap / tuning.smoothingTau)
            smoothedDirection = Self.unit(current + (unit - current) * alpha) ?? unit
        } else {
            smoothedDirection = unit
        }
        lastDirectionAt = now
    }

    private mutating func updateTrend(now: Date) {
        guard let meters = smoothedMeters else { return }
        guard let anchor = trendAnchor else {
            trendAnchor = (meters, now)
            return
        }
        let delta = meters - anchor.meters
        if delta <= -tuning.trendDeadband {
            trend = .closer
            trendAnchor = (meters, now)
        } else if delta >= tuning.trendDeadband {
            trend = .farther
            trendAnchor = (meters, now)
        } else if now.timeIntervalSince(anchor.at) >= tuning.trendSteadyAfter {
            trend = .steady
            trendAnchor = (meters, now)
        }
    }

    private mutating func updateArrivedLatch() {
        guard let meters = smoothedMeters else { return }
        if isArrived {
            if meters > tuning.arrivedExit { isArrived = false }
        } else if meters <= tuning.arrivedEnter {
            isArrived = true
        }
    }

    // MARK: - Deciding what to say

    private mutating func recompute(now: Date) {
        let distanceAge = elapsed(since: lastDistanceAt, now: now)
        let directionAge = elapsed(since: lastDirectionAt, now: now)
        let distanceFresh = distanceAge <= tuning.staleAfter
        let directionFresh = directionAge <= tuning.directionGrace

        if !distanceFresh, !directionFresh {
            state = lastReadingAt.map { .signalLost(lastMeters: smoothedMeters, at: $0) }
                ?? (hasPeer ? .acquiring : .waitingForPeer)
            return
        }
        if distanceFresh, isArrived, let meters = smoothedMeters {
            state = .arrived(meters: meters)
            return
        }
        if directionFresh, let direction = smoothedDirection {
            let meters = distanceFresh ? smoothedMeters : nil
            if let azimuth = Self.azimuth(of: direction, minimumPlanar: tuning.minimumPlanarComponent) {
                state = .directed(
                    meters: meters,
                    heading: ProximityHeading(azimuth: azimuth,
                                              isConfirmed: directionAge <= tuning.directionConfirmWindow)
                )
            } else {
                // We have a vector — it is the phone's posture that makes it
                // unusable, and that is the user's to fix. Say which.
                state = .holdPhoneFlat(meters: meters)
            }
            return
        }
        if distanceFresh, let meters = smoothedMeters {
            state = .distanceOnly(meters: meters, trend: trend)
            return
        }
        state = hasPeer ? .acquiring : .waitingForPeer
    }

    // MARK: - Helpers

    /// States in which a reading or a tick must change nothing: either the
    /// radar is not running, or something happened that a new sample cannot
    /// undo on its own.
    private var isBlocked: Bool {
        switch state {
        case .idle, .unsupported, .permissionDenied, .peerCannotRange,
             .peerLeft, .paused, .failed:
            return true
        default:
            return false
        }
    }

    private var lastReadingAt: Date? {
        [lastDistanceAt, lastDirectionAt].compactMap { $0 }.max()
    }

    /// `.infinity` when there is no previous reading, and also when the clock
    /// runs backwards — a negative gap would make the filter's alpha explode.
    private func elapsed(since date: Date?, now: Date) -> TimeInterval {
        guard let date else { return .infinity }
        let gap = now.timeIntervalSince(date)
        return gap >= 0 ? gap : .infinity
    }

    private mutating func resetReadings() {
        smoothedMeters = nil
        smoothedDirection = nil
        lastDistanceAt = nil
        lastDirectionAt = nil
        isArrived = false
        trend = .unknown
        trendAnchor = nil
    }

    private static func unit(_ vector: SIMD3<Double>) -> SIMD3<Double>? {
        let length = (vector.x * vector.x + vector.y * vector.y + vector.z * vector.z).squareRoot()
        guard length.isFinite, length > 1e-6 else { return nil }
        return vector / length
    }

    /// Full-circle bearing in the phone's own screen plane. `atan2(x, y)`, not
    /// the `asin(x)` of Apple's NIPeekaboo sample: `asin` folds the circle onto
    /// ±90°, so a peer standing directly BEHIND the user comes out as "straight
    /// ahead" — the one error that makes someone walk away from their friend.
    ///
    /// nil when the in-plane projection is shorter than `minimumPlanar`: the
    /// peer is then near the screen's normal axis and the in-plane angle is
    /// noise. The caller turns that into `.holdPhoneFlat`, not into a guess.
    ///
    /// The out-of-plane component is never surfaced as elevation: it is the
    /// noisiest axis, the UI is a flat arrow, and `verticalDirectionEstimate` —
    /// the coarse above/below hint that would be trustworthy — is documented as
    /// requiring camera assistance, which this feature deliberately never enables.
    private static func azimuth(of direction: SIMD3<Double>, minimumPlanar: Double) -> Double? {
        let planar = (direction.x * direction.x + direction.y * direction.y).squareRoot()
        guard planar >= minimumPlanar else { return nil }
        return atan2(direction.x, direction.y)
    }
}
