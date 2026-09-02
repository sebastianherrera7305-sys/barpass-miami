import CoreLocation

@MainActor
final class LocationService: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var onceCompletion: CheckedContinuation<CLLocationCoordinate2D?, Never>?
    var onUpdate: ((Double, Double, Double) -> Void)?

    /// requestLocation() failing with .locationUnknown is not a real
    /// failure — Apple's own docs for the call say it means "temporarily
    /// unable to get a fix, try again", the normal state indoors or between
    /// tall buildings. A nightclub inside a Brickell high-rise is exactly
    /// that case: TestFlight feedback reported the check-in button doing
    /// nothing while standing right at the venue. The old code resumed
    /// `nil` on the very first .locationUnknown, which surfaced as a dead
    /// button or a wrong "enable location" message with location already
    /// on. Retried a few times before giving up; capped so a genuinely
    /// unavailable signal still resolves instead of hanging the caller.
    private var retriesRemaining = 0
    private static let maxRetries = 4

    /// The accuracy of the last coordinate resolved by requestOnce() —
    /// read this right after awaiting it. iOS reports the actual
    /// uncertainty radius (in meters) alongside every fix; a caller that
    /// compares raw distance-to-venue against a fixed threshold without
    /// this is comparing a real number to a fuzzy one as if both were
    /// exact. Indoors or between tall buildings (a nightclub inside a
    /// Brickell high-rise) this is routinely 60-150m even on a resolved
    /// fix, which is what made check-in fail while standing at the venue.
    private(set) var lastHorizontalAccuracy: CLLocationAccuracy?

    /// True once iOS has permanently refused the prompt (user tapped
    /// "Don't Allow", or a parent/MDM restriction). requestWhenInUseAuthorization()
    /// is a silent no-op in this state — Apple shows the system prompt at
    /// most once per app install, never again — so "activá tu ubicación"
    /// with no further instruction is a dead end: the tap that produced it
    /// looks identical to a temporary GPS miss, but no retry will ever fix
    /// it. Callers use this to route to Settings instead of retrying.
    var isPermissionPermanentlyDenied: Bool {
        manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10
    }

    func requestOnce() async -> CLLocationCoordinate2D? {
        // Resume any abandoned continuation before creating a new one
        if let existing = onceCompletion {
            onceCompletion = nil
            existing.resume(returning: nil)
        }
        retriesRemaining = Self.maxRetries
        return await withCheckedContinuation { continuation in
            onceCompletion = continuation
            manager.requestWhenInUseAuthorization()
            manager.requestLocation()
        }
    }

    func startUpdating() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
    }

    // MARK: - CLLocationManagerDelegate
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let coord = loc.coordinate
        onUpdate?(coord.latitude, coord.longitude, loc.horizontalAccuracy)

        if let cont = onceCompletion {
            onceCompletion = nil
            lastHorizontalAccuracy = loc.horizontalAccuracy
            cont.resume(returning: coord)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        #if DEBUG
        print("[Location] Error:", error)
        #endif
        if let clError = error as? CLError, clError.code == .locationUnknown, retriesRemaining > 0 {
            retriesRemaining -= 1
            manager.requestLocation()
            return
        }
        if let cont = onceCompletion {
            onceCompletion = nil
            cont.resume(returning: nil)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            onceCompletion?.resume(returning: nil)
            onceCompletion = nil
        }
    }
}
