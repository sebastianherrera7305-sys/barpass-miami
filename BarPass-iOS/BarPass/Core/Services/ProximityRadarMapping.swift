import Foundation
import NearbyInteraction
import simd

// Everything NearbyInteraction says, translated into our vocabulary in one
// place. Kept apart from `ProximityRadar` so the live service reads as policy
// and this reads as a dictionary — and so the state machine and its tests
// never need to import NearbyInteraction at all.

extension ProximityCapability {
    /// `supportsPreciseDistanceMeasurement == false` covers both "this phone
    /// has no U1/U2 chip" and "UWB is switched off by regulation here". iOS
    /// does not tell them apart, so neither do we.
    init(_ capabilities: any NIDeviceCapability) {
        guard capabilities.supportsPreciseDistanceMeasurement else {
            self = .cannotRange
            return
        }
        self = capabilities.supportsDirectionMeasurement ? .distanceAndDirection : .distanceOnly
    }
}

extension ProximitySample {
    /// Reduced to plain `Sendable` values at the point of receipt, because
    /// `NINearbyObject` does not cross an isolation boundary cleanly. Both
    /// fields are optional in the SDK and stay optional here: an update that
    /// carries neither told us nothing, and must not be dressed up as a reading.
    init(_ object: NINearbyObject) {
        self.init(
            distanceMeters: object.distance.map(Double.init),
            direction: object.direction.map { SIMD3<Double>(Double($0.x), Double($0.y), Double($0.z)) }
        )
    }
}

/// What an `NISession` invalidation means for the person holding the phone.
/// Three outcomes, because "the user said no" and "this hardware cannot" are
/// different sentences and neither is a generic failure.
enum ProximityInvalidation: Sendable {
    case permissionDenied
    case platformUnsupported
    case fatal(ProximityRadarFailure)

    init(_ error: any Error) {
        guard let code = (error as? NIError)?.code else {
            self = .fatal(.sessionFailed)
            return
        }
        switch code {
        case .userDidNotAllow: self = .permissionDenied
        case .unsupportedPlatform: self = .platformUnsupported
        case .incompatiblePeerDevice: self = .fatal(.peerDeviceIncompatible)
        case .activeSessionsLimitExceeded, .activeExtendedDistanceSessionsLimitExceeded:
            self = .fatal(.tooManySessions)
        case .resourceUsageTimeout: self = .fatal(.rangingTimedOutBySystem)
        default: self = .fatal(.sessionFailed)
        }
    }
}
