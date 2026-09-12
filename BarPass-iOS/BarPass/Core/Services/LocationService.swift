import CoreLocation
import Foundation

/// One resolved position plus how fuzzy it is. iOS reports the actual
/// uncertainty radius (meters) alongside every fix; a caller that compares
/// raw distance-to-venue against a fixed threshold without this is
/// comparing a real number to a fuzzy one as if both were exact.
struct LocationFix: Sendable {
    let coordinate: CLLocationCoordinate2D
    /// Meters. Indoors or between tall buildings (a nightclub inside a
    /// Brickell high-rise) this is routinely 60-150m even on a resolved fix.
    let horizontalAccuracy: CLLocationAccuracy
    /// True when the fix only cleared `LocationPolicy.maxUsableAccuracy`
    /// at the deadline, not `acceptAccuracy` — good enough to use, but the
    /// caller should not pretend it is precise.
    let isCoarse: Bool
}

/// Why a location request produced no usable fix. Every case maps to a
/// different thing the UI must tell the user — collapsing these into `nil`
/// is what made check-in look "broken" (see LocationService).
enum LocationError: Error, Sendable {
    /// User tapped "Don't Allow" (or MDM/parental restriction). iOS shows
    /// the system prompt at most once per install; only Settings fixes this.
    case permissionDenied
    /// The prompt was shown but never answered within the guard window
    /// (app backgrounded mid-prompt, or the prompt could not be shown).
    case permissionNotDetermined
    /// Permission granted but with "Precise Location" off — fixes come back
    /// ~1-5km wide, which cannot satisfy a policy that needs meters. Only
    /// Settings fixes this (there is no temporary-full-accuracy purpose key
    /// in Info.plist, so we cannot ask in-app).
    case preciseLocationOff
    /// Waited the full policy timeout and the best fix received was still
    /// wider than `maxUsableAccuracy` (or none arrived). `best` is that fix,
    /// for callers whose use is loose enough to take it anyway.
    case timedOut(best: LocationFix?)
    /// CoreLocation reported a hard failure other than "temporarily unknown".
    case unavailable(underlying: any Error)
}

/// How good a fix has to be, and how long to wait for it. Both numbers are
/// meaningful only relative to what the caller does with the coordinate —
/// see the presets.
struct LocationPolicy: Sendable {
    /// Resolve the moment a fix at least this good arrives.
    let acceptAccuracy: CLLocationAccuracy
    /// At the deadline, the best fix so far is returned (flagged coarse)
    /// only if it is at least this good; otherwise `.timedOut`.
    let maxUsableAccuracy: CLLocationAccuracy
    let timeout: Duration

    /// Check-in against `CheckInStore.maxCheckInDistanceMeters` (150m).
    ///
    /// - `acceptAccuracy` 100m equals `CheckInStore.maxAccuracyForgivenessMeters`:
    ///   the store forgives up to 100m of reported uncertainty before judging
    ///   distance, so a fix at or under 100m is fully "meaningful" at a 150m
    ///   radius and there is nothing to gain by waiting for GPS to refine it.
    /// - `maxUsableAccuracy` 200m is the honest ceiling. With the 100m
    ///   forgiveness cap, a 200m-wide fix reading 250m from the pin passes
    ///   as 150m effective — someone who is really ~450m away (one long
    ///   block) could sneak through, and that is the most we accept.
    ///   A 500m-wide fix against a 150m radius is meaningless: raw distance
    ///   carries no information about whether the person is inside, so it
    ///   is rejected as `.timedOut(best:)` rather than judged as "too far"
    ///   (which would be a lie — we do not know how far they are).
    /// - 8s: Wi-Fi/cell positioning usually lands a ≤100m fix in 1-3s even
    ///   indoors; GPS inside a club can take 20-40s, which nobody waits
    ///   for at a door. A retry after a timeout benefits from the warmed
    ///   radio, so failing fast and saying why beats a long spinner.
    static let checkIn = LocationPolicy(acceptAccuracy: 100, maxUsableAccuracy: 200, timeout: .seconds(8))

    /// Neighborhood-level is enough: distance-based scoring, the concierge's
    /// "near you" ranking, Uber pickup pre-fill. Anything under ~3km beats
    /// having no location at all for these.
    static let coarse = LocationPolicy(acceptAccuracy: 500, maxUsableAccuracy: 3_000, timeout: .seconds(8))
}

/// One-shot location acquisition with an explicit permission handshake and
/// an explicit accuracy/time budget.
///
/// History, so nobody re-introduces the bugs:
/// - The old `requestOnce()` called `requestWhenInUseAuthorization()` and
///   `requestLocation()` back to back, and its authorization callback
///   treated `.notDetermined` as a failure — so the very first check-in on
///   a fresh install dropped the request while the permission prompt was
///   still on screen. The user tapped Allow and nothing happened; the
///   second tap worked, and most people never made a second tap. That is
///   the Factory Town "no está chequeando la ubicación" report.
/// - `requestLocation()` failing with `.locationUnknown` is not a failure:
///   Apple's docs say "temporarily unable to get a fix, try again". The
///   code before that resumed `nil` on the first one.
/// - Every failure used to resolve to `nil`, so the UI could not tell
///   "denied" from "GPS slow" from "Precise Location off".
///
/// Isolation: this class is `@MainActor`, and every `CLLocationManager` is
/// created inside a main-actor `init`, so CoreLocation delivers delegate
/// callbacks on the main run loop. The delegate methods are still declared
/// `nonisolated` and hop through `onMain` instead of assuming isolation:
/// build 22/26/50 crashed with SIGTRAP because a `BGTaskScheduler` closure
/// assumed main-actor state off-main, and the same trap exists for
/// `@preconcurrency` delegate conformances. `onMain` never traps — it runs
/// inline when already on main and enqueues otherwise.
@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    private var pending: [CheckedContinuation<LocationFix, any Error>] = []
    private var policy: LocationPolicy = .coarse
    private var bestFix: LocationFix?
    private var deadlineTask: Task<Void, Never>?
    private var isAcquiring = false
    private var isAwaitingAuthorization = false

    /// Fixes older than this are CoreLocation's cache, not the present.
    /// A five-minute-old fix is where the Uber dropped you, not the club.
    private static let maxFixAge: TimeInterval = 60
    /// If the prompt is up and nobody answers (or it never appeared), stop
    /// spinning eventually. Generous on purpose — reading a permission
    /// dialog takes as long as it takes.
    private static let authorizationGuard: Duration = .seconds(45)

    /// True once iOS has permanently refused the prompt (user tapped
    /// "Don't Allow", or a parent/MDM restriction). `requestWhenInUseAuthorization()`
    /// is a silent no-op in this state — Apple shows the system prompt at
    /// most once per app install, never again — so callers route to
    /// Settings instead of retrying.
    var isPermissionPermanentlyDenied: Bool {
        manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.distanceFilter = kCLDistanceFilterNone
    }

    /// Resolves with the first fix that satisfies `policy`, or throws a
    /// `LocationError` that says exactly what stood in the way. Concurrent
    /// callers on the same instance share one acquisition.
    func requestFix(_ policy: LocationPolicy = .coarse) async throws -> LocationFix {
        if !isAcquiring && !isAwaitingAuthorization {
            self.policy = policy
        }
        return try await withCheckedThrowingContinuation { continuation in
            pending.append(continuation)
            guard !isAcquiring, !isAwaitingAuthorization else { return }
            route(status: manager.authorizationStatus)
        }
    }

    /// Convenience for callers that can live without a location: any
    /// error becomes `nil`. Use `requestFix` where the UI must explain why.
    func requestOnce(_ policy: LocationPolicy = .coarse) async -> CLLocationCoordinate2D? {
        do {
            return try await requestFix(policy).coordinate
        } catch LocationError.timedOut(let best?) {
            return best.coordinate
        } catch {
            return nil
        }
    }

    // MARK: - State machine

    private func route(status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined:
            // Step 1 of the fix: keep the continuation, ask, and wait for
            // locationManagerDidChangeAuthorization to carry on. Nothing
            // is dropped, and no deadline runs while the prompt is up.
            isAwaitingAuthorization = true
            manager.requestWhenInUseAuthorization()
            deadlineTask?.cancel()
            deadlineTask = Task { [weak self] in
                try? await Task.sleep(for: Self.authorizationGuard)
                guard !Task.isCancelled, let self, self.isAwaitingAuthorization else { return }
                self.isAwaitingAuthorization = false
                self.finish(.failure(LocationError.permissionNotDetermined))
            }
        case .denied, .restricted:
            finish(.failure(LocationError.permissionDenied))
        case .authorizedWhenInUse, .authorizedAlways:
            beginAcquisition()
        @unknown default:
            finish(.failure(LocationError.permissionDenied))
        }
    }

    private func beginAcquisition() {
        // "Precise Location: Off" yields fixes several km wide. For a policy
        // that needs meters, waiting would only end in a misleading
        // "couldn't pin your location" — say what is actually wrong.
        if manager.accuracyAuthorization == .reducedAccuracy, policy.maxUsableAccuracy < 1_000 {
            finish(.failure(LocationError.preciseLocationOff))
            return
        }
        isAcquiring = true
        bestFix = nil
        // Ask for what the policy accepts, not "best": CoreLocation
        // reaches HundredMeters from Wi-Fi/cell in seconds and only spins
        // up GPS for tighter targets, which is the 20-40s indoor wait.
        manager.desiredAccuracy = policy.acceptAccuracy <= 100
            ? kCLLocationAccuracyHundredMeters
            : kCLLocationAccuracyKilometer
        manager.startUpdatingLocation()

        deadlineTask?.cancel()
        let timeout = policy.timeout
        deadlineTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, let self, self.isAcquiring else { return }
            self.resolveAtDeadline()
        }
    }

    private func resolveAtDeadline() {
        if let best = bestFix, best.horizontalAccuracy <= policy.maxUsableAccuracy {
            finish(.success(LocationFix(coordinate: best.coordinate,
                                        horizontalAccuracy: best.horizontalAccuracy,
                                        isCoarse: true)))
        } else {
            finish(.failure(LocationError.timedOut(best: bestFix)))
        }
    }

    private func finish(_ result: Result<LocationFix, any Error>) {
        deadlineTask?.cancel()
        deadlineTask = nil
        if isAcquiring { manager.stopUpdatingLocation() }
        isAcquiring = false
        isAwaitingAuthorization = false
        let waiters = pending
        pending = []
        for continuation in waiters {
            continuation.resume(with: result)
        }
    }

    private func handle(coordinate: CLLocationCoordinate2D, accuracy: CLLocationAccuracy, age: TimeInterval) {
        guard isAcquiring else { return }
        // Negative accuracy means "invalid" per CLLocation docs.
        guard accuracy >= 0, age <= Self.maxFixAge else { return }
        if let current = bestFix, current.horizontalAccuracy <= accuracy {
            // Not an improvement on what we already hold.
        } else {
            bestFix = LocationFix(coordinate: coordinate, horizontalAccuracy: accuracy, isCoarse: false)
        }
        if accuracy <= policy.acceptAccuracy {
            finish(.success(LocationFix(coordinate: coordinate, horizontalAccuracy: accuracy, isCoarse: false)))
        }
    }

    private func handle(error: any Error) {
        let code = (error as? CLError)?.code
        switch code {
        case .locationUnknown?:
            // Not a failure — "temporarily unable to get a fix". Updates
            // keep flowing; the deadline decides.
            return
        case .denied?:
            finish(.failure(LocationError.permissionDenied))
        default:
            guard isAcquiring else { return }
            if let best = bestFix, best.horizontalAccuracy <= policy.maxUsableAccuracy {
                finish(.success(LocationFix(coordinate: best.coordinate,
                                            horizontalAccuracy: best.horizontalAccuracy,
                                            isCoarse: best.horizontalAccuracy > policy.acceptAccuracy)))
            } else {
                finish(.failure(LocationError.unavailable(underlying: error)))
            }
        }
    }

    private func handleAuthorizationChange(_ status: CLAuthorizationStatus) {
        // CoreLocation fires this once right after the manager is created,
        // with whatever the current status is. With nothing pending it is
        // noise — the old code called requestLocation() here on every
        // init, a stray fetch nobody had asked for.
        guard !pending.isEmpty else { return }
        switch status {
        case .notDetermined:
            // Prompt is still up (or about to be). Keep waiting.
            return
        case .authorizedWhenInUse, .authorizedAlways:
            // Step 2 of the fix: the user tapped Allow — resume the very
            // request that triggered the prompt, instead of making them
            // tap again.
            guard !isAcquiring else { return }
            isAwaitingAuthorization = false
            deadlineTask?.cancel()
            beginAcquisition()
        case .denied, .restricted:
            finish(.failure(LocationError.permissionDenied))
        @unknown default:
            finish(.failure(LocationError.permissionDenied))
        }
    }

    // MARK: - CLLocationManagerDelegate (nonisolated; see class comment)

    /// Runs `body` on the main actor without ever trapping: inline when the
    /// callback already arrived on main (the normal case for a manager
    /// created on main), enqueued otherwise.
    nonisolated private func onMain(_ body: @escaping @MainActor @Sendable () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(body)
        } else {
            Task { @MainActor in body() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Extract plain Sendable values before hopping — CLLocation itself
        // does not cross the isolation boundary cleanly.
        let now = Date()
        let samples: [(CLLocationCoordinate2D, CLLocationAccuracy, TimeInterval)] = locations.map {
            ($0.coordinate, $0.horizontalAccuracy, now.timeIntervalSince($0.timestamp))
        }
        onMain { [weak self] in
            guard let self else { return }
            for (coordinate, accuracy, age) in samples {
                self.handle(coordinate: coordinate, accuracy: accuracy, age: age)
                if !self.isAcquiring { break }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        #if DEBUG
        print("[Location] Error:", error)
        #endif
        onMain { [weak self] in self?.handle(error: error) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        onMain { [weak self] in self?.handleAuthorizationChange(status) }
    }
}
