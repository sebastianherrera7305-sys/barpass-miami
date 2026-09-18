import Foundation
import simd

// MARK: - What the two phones can physically do

/// What ranging is possible for THIS PAIR of phones. Read from
/// `NISession.deviceCapabilities` for us and from the peer's discovery token
/// for them, then reduced to the weaker of the two: the direction vector needs
/// both radios, so one iPhone SE in the pair means nobody gets an arrow.
enum ProximityCapability: String, Sendable, Equatable {
    /// No precise ranging at all. iOS does not say whether that is "no U1/U2
    /// chip" (every iPhone SE, everything before the iPhone 11) or "UWB is
    /// switched off by regulation where this phone is", so neither do we —
    /// one case, not two invented ones.
    case cannotRange
    /// Distance yes, arrow never.
    case distanceOnly
    case distanceAndDirection

    func reduced(with peer: ProximityCapability) -> ProximityCapability {
        if self == .cannotRange || peer == .cannotRange { return .cannotRange }
        if self == .distanceOnly || peer == .distanceOnly { return .distanceOnly }
        return .distanceAndDirection
    }
}

// MARK: - Transport seam (implemented by piece 4, against the backend)

/// What we ask the transport to say about us. Two cases because silence is
/// ambiguous: a phone that cannot range produces no discovery token, and
/// without an explicit announcement the far side would sit on "waiting for
/// them" forever instead of being told to look for the colour.
enum ProximityAnnouncement: Sendable, Equatable {
    case token(Data)
    case cannotRange
}

/// What the transport reports about the far side.
enum ProximityPeerEvent: Sendable {
    case token(Data)
    case peerCannotRange
    /// They closed the app or ended the session. Different from losing the
    /// radio: nothing comes back on its own.
    case peerLeft
    /// The transport itself broke (no network, expired auth). We can no longer
    /// learn anything NEW about the far side — which is not the same as the
    /// far side being gone, and must never be shown as if it were.
    case channelFailed(any Error)
}

/// The minimum a transport has to do: say one thing about us, report what it
/// hears about them, stop when asked. It never sees an `NIDiscoveryToken`,
/// only opaque `Data`, so piece 4 needs no NearbyInteraction dependency and
/// can be faked in a test with three lines.
/// All three are `async` so that an implementation may be `@MainActor` or an
/// `actor` — a synchronous requirement would force every implementer (and every
/// fake in a test) to be nonisolated and hand-synchronised for no benefit.
protocol ProximityTokenChannel: Sendable {
    func publish(_ announcement: ProximityAnnouncement) async throws
    func events() async -> AsyncStream<ProximityPeerEvent>
    func close() async
}

// MARK: - Readings

/// One NearbyInteraction update, reduced to plain `Sendable` values before it
/// crosses an isolation boundary. Either field can be absent on any given
/// update; both absent means the update told us nothing.
struct ProximitySample: Sendable, Equatable {
    var distanceMeters: Double?
    /// Unit vector in the PHONE's own frame, straight from `NINearbyObject`.
    var direction: SIMD3<Double>?
}

/// Where to point. Device-relative, which is why this needs no compass.
struct ProximityHeading: Sendable, Equatable {
    /// Radians in the phone's own screen plane: 0 = out of the top edge,
    /// positive = to the user's right, ±π = directly behind them. Rotate the
    /// arrow by this and it points — the vector is already relative to the hand
    /// holding the phone, so there is no compass and no true north involved.
    var azimuth: Double
    /// `false` when we are drawing a vector that last arrived up to
    /// `directionGrace` ago rather than one confirmed right now. The UI MUST
    /// dim it: a held vector is wrong the instant the user turns, and a
    /// confident stale arrow is the single worst thing this feature can do.
    var isConfirmed: Bool
}

/// The honest replacement for "hotter / colder" — computed from real UWB
/// distance (±10 cm), never from radio strength. See the note on
/// `ProximityTuning.trendDeadband`.
enum ProximityTrend: String, Sendable, Equatable {
    case closer, farther, steady
    /// Not enough movement yet to call it. Shown as nothing, not as "steady".
    case unknown
}

/// Things that end the radar and are nobody's fault at the UI layer.
enum ProximityRadarFailure: String, Sendable, Equatable {
    /// `NSNearbyInteractionUsageDescription` is missing from Info.plist. A
    /// build mistake, not a user condition — traps in DEBUG, degrades here.
    case missingUsageDescription
    /// `NIError.incompatiblePeerDevice`.
    case peerDeviceIncompatible
    /// `NIError.activeSessionsLimitExceeded` — too many NI sessions at once.
    case tooManySessions
    /// `NIError.resourceUsageTimeout` — iOS ended a session that ran too long.
    case rangingTimedOutBySystem
    /// The transport could not carry the handshake at all.
    case channelUnavailable
    /// The peer's token arrived but could not be decoded.
    case invalidToken
    /// Anything else NearbyInteraction reports as fatal.
    case sessionFailed
}

// MARK: - The state

/// Every state says one thing to the person holding the phone. There is no
/// case that means "something is happening, we are not sure what" — when we do
/// not know, the state is named after not knowing and is rendered as such.
enum ProximityRadarState: Sendable, Equatable {
    /// Not started.
    case idle
    /// This phone cannot range. There will never be an arrow here; the caller
    /// should go straight to the colour beacon.
    case unsupported
    /// The user declined the Nearby Interactions prompt. Only Settings changes it.
    case permissionDenied
    /// We announced ourselves; the other person has not opened their radar yet.
    case waitingForPeer
    /// Their phone cannot range. Their side is showing the colour beacon.
    case peerCannotRange
    /// Both are in, no measurement has landed yet.
    case acquiring
    /// How far, not which way — beyond the arrow's working envelope, or the
    /// phone is not pointed anywhere useful.
    case distanceOnly(meters: Double, trend: ProximityTrend)
    /// Arrow live. `meters` is nil in the rare update that carries a direction
    /// and no distance: we know the way, not the far.
    case directed(meters: Double?, heading: ProximityHeading)
    /// We have a direction vector, but the phone is held so that the peer sits
    /// almost along the screen's normal axis, where the in-plane angle is
    /// noise. Unlike every other reason for having no arrow, this one the user
    /// can fix in a second — so it gets its own sentence instead of quietly
    /// degrading to "distance only".
    case holdPhoneFlat(meters: Double?)
    /// Close enough that the arrow is noise. Stop pointing, start looking.
    case arrived(meters: Double)
    /// We had them and lost them. `at` is when the last reading actually
    /// arrived, so the UI can age it honestly instead of freezing a number.
    case signalLost(lastMeters: Double?, at: Date)
    /// They ended their session.
    case peerLeft
    /// Our app left the foreground, so NearbyInteraction stopped. Phone-to-
    /// phone ranging is foreground-only by Apple's design, not a bug to fix.
    case paused
    case failed(ProximityRadarFailure)
}

extension ProximityRadarState {
    /// One sentence per state, decided here so that no screen can invent a
    /// friendlier one that promises more than we measured.
    var messageKey: String {
        switch self {
        case .idle: return "radar.idle"
        case .unsupported: return "radar.unsupported"
        case .permissionDenied: return "radar.permissionDenied"
        case .waitingForPeer: return "radar.waitingForPeer"
        case .peerCannotRange: return "radar.peerCannotRange"
        case .acquiring: return "radar.acquiring"
        case .distanceOnly(_, let trend):
            switch trend {
            case .closer: return "radar.distanceOnly.closer"
            case .farther: return "radar.distanceOnly.farther"
            case .steady, .unknown: return "radar.distanceOnly"
            }
        case .directed(_, let heading):
            return heading.isConfirmed ? "radar.directed" : "radar.directed.unconfirmed"
        case .holdPhoneFlat: return "radar.holdPhoneFlat"
        case .arrived: return "radar.arrived"
        case .signalLost: return "radar.signalLost"
        case .peerLeft: return "radar.peerLeft"
        case .paused: return "radar.paused"
        case .failed(let failure): return "radar.failed.\(failure.rawValue)"
        }
    }

    /// The only state in which an arrow may be drawn. Anything else that draws
    /// one is drawing a lie.
    var heading: ProximityHeading? {
        if case .directed(_, let heading) = self { return heading }
        return nil
    }

    /// The distance we are willing to stand behind right now. Deliberately nil
    /// in `.signalLost` — the last number is in the payload, for a UI that
    /// labels it as old, not for one that keeps displaying it as current.
    var meters: Double? {
        switch self {
        case .distanceOnly(let meters, _): return meters
        case .directed(let meters, _): return meters
        case .arrived(let meters): return meters
        case .holdPhoneFlat(let meters): return meters
        default: return nil
        }
    }

    /// Nothing the passage of time can change: either the radar is not
    /// running, or it is waiting on something no clock will deliver. Excludes
    /// `.paused`, which is waiting on the app coming back to the foreground.
    var isSettled: Bool {
        switch self {
        case .idle, .unsupported, .permissionDenied, .peerCannotRange, .peerLeft, .failed:
            return true
        default:
            return false
        }
    }

    /// When the radar has nothing left to offer and the colour beacon is the
    /// honest next move.
    var shouldFallBackToBeacon: Bool {
        switch self {
        case .unsupported, .peerCannotRange, .arrived, .failed, .permissionDenied: return true
        default: return false
        }
    }
}

// MARK: - Tuning

/// Every number here is a judgement call with a reason. Changing one without
/// reading the reason is how this feature starts lying.
struct ProximityTuning: Sendable {
    /// Time constant of the distance filter. `alpha = 1 - exp(-dt/tau)`, so the
    /// smoothing is defined in SECONDS and does not change if NearbyInteraction
    /// delivers at 5 Hz instead of the ~10 Hz we observe — a sample-count filter
    /// would silently get twice as laggy. 0.4 s kills the ±10 cm jitter while
    /// costing about half a step of lag at walking pace.
    var smoothingTau: TimeInterval = 0.4
    /// No distance reading for this long and the state changes. 2 s is ~20
    /// missed updates: far past "one dropped packet", far short of the ~10 s
    /// NearbyInteraction itself takes to declare a timeout. The UI must not
    /// keep a live-looking number for those 10 s.
    var staleAfter: TimeInterval = 2.0
    /// How long a direction vector may keep drawing the arrow after the last
    /// one arrived. A person turning in place sweeps roughly 180°/s, so a held
    /// vector is off by up to ~110° at the end of this window — which is why
    /// anything past `directionConfirmWindow` is flagged unconfirmed and the UI
    /// dims it, and why the window is not longer.
    var directionGrace: TimeInterval = 0.6
    /// Inside this the arrow is confirmed-live (2-3 expected updates).
    var directionConfirmWindow: TimeInterval = 0.25
    /// Stop giving an arrow at or below this. Between two people standing up,
    /// a 30 cm sway moves the true bearing by 11° at 1.5 m and by 21° at 0.8 m,
    /// so the arrow starts spinning from real motion, not sensor error — and at
    /// 1.5 m you can already see the person. Pointing is over; looking begins.
    var arrivedEnter: Double = 1.5
    /// Leave "arrived" only above this. The gap is hysteresis: without it the
    /// state flaps every time the smoothed value crosses the line.
    var arrivedExit: Double = 2.5
    /// Net change required to call a trend. Walking is ~1.3 m/s, so 0.75 m is
    /// about 0.6 s of walking — an order of magnitude above the ±10 cm reading
    /// noise and above the ~±30 cm of someone shifting their weight in place.
    var trendDeadband: Double = 0.75
    /// No net change for this long and the trend is `.steady` rather than a
    /// stale `.closer` from the last time they moved.
    var trendSteadyAfter: TimeInterval = 3.0
    /// Shortest in-plane projection of the direction vector we will still turn
    /// into an arrow. 0.3 = sin(17.5°): below it the peer sits within ~17° of
    /// the screen's normal axis — phone held upright with them in front of or
    /// behind its face — and the in-plane angle there is dominated by noise.
    var minimumPlanarComponent: Double = 0.3

    static let `default` = ProximityTuning()
}
