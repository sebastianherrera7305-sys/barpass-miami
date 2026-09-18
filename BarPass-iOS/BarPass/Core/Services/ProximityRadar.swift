import Combine
import Foundation
import NearbyInteraction
import simd

/// Precision finding between two people, the way Find My points at an AirTag:
/// a distance, and — when the radios and the geometry allow it — an arrow.
///
/// Three constraints are settled and should not be relitigated:
/// - Phone-to-phone NearbyInteraction runs ONLY with both apps in the
///   foreground; Apple allows no background ranging between iPhones. That fits
///   — two people open this precisely when they are looking for each other.
/// - UWB needs an iPhone 11 or newer and exists in no iPhone SE. There is no
///   arrow on those phones and never will be: `.unsupported`, then the beacon.
/// - Direction needs BOTH radios, close range and a favourable angle; distance
///   survives much further out than direction does.
///
/// **Why there is no Bluetooth "hotter / colder" fallback.** RSSI-to-distance
/// runs on `RSSI = A - 10·n·log10(d)`; indoors n ≈ 3, so the ±6 dB swing you
/// get standing still is a distance error of 10^(6/30) ≈ 1.6× — "3 m" means
/// 1.9-4.7 m. Worse, a human body between the phones costs 10-20 dB at 2.4 GHz;
/// at 15 dB that is 10^(15/30) ≈ 3.2×, so a friend 2 m away with their back
/// turned reads FARTHER than a stranger 6 m away in clear line of sight. In a
/// packed room that is not imprecision, it is inversion — the needle points
/// away from the person, and a safety feature that sends someone walking the
/// wrong way is worse than one that admits it does not know. It buys no
/// availability either: iOS background BLE advertising is invisible to other
/// iOS devices, so it would be foreground-only too. Decision: no RSSI
/// fallback. A phone that cannot range says so, and the colour takes over.
@MainActor
final class ProximityRadar: NSObject, ObservableObject, NISessionDelegate {

    @Published private(set) var state: ProximityRadarState = .idle

    private let channel: any ProximityTokenChannel
    private var core: ProximityRadarCore
    private var session: NISession?
    private var peerToken: NIDiscoveryToken?
    private var eventsTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var lastRunAt: Date?
    private var isRunning = false

    /// Resolution of the staleness clock: how late "we lost them" can be. A
    /// quarter of a step at walking pace, well inside the 2 s window it polices.
    private static let tickInterval: Duration = .milliseconds(250)
    /// Floor between `run(_:)` calls, so a flapping peer is not a hot loop.
    private static let minimumRerunInterval: TimeInterval = 2

    init(channel: any ProximityTokenChannel,
         tuning: ProximityTuning = .default,
         capability: ProximityCapability = ProximityRadar.deviceCapability()) {
        self.channel = channel
        self.core = ProximityRadarCore(capability: capability, tuning: tuning)
        super.init()
    }

    nonisolated static func deviceCapability() -> ProximityCapability {
        ProximityCapability(NISession.deviceCapabilities)
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        guard Self.hasUsageDescription else {
            // A build mistake, not a user condition: loud in DEBUG, honest in
            // release instead of an unexplained invalidation at runtime.
            assertionFailure("NSNearbyInteractionUsageDescription missing from Info.plist; NearbyInteraction cannot run.")
            core.fail(.missingUsageDescription)
            publish()
            return
        }
        core.start()
        publish()
        listenToChannel()
        guard core.capability != .cannotRange else {
            // Still listening, so "they left" can close the screen — but we say
            // no token is coming, instead of leaving them waiting on one forever.
            announce(.cannotRange)
            return
        }
        let session = NISession()
        session.delegate = self
        // Explicit even though nil already means main. Builds 22/26/50 died of
        // exactly this: a framework callback landing off-main in main-actor state.
        session.delegateQueue = .main
        self.session = session
        guard let token = session.discoveryToken,
              let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else {
            core.fail(.sessionFailed)
            publish()
            return
        }
        announce(.token(data))
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        tickTask?.cancel()
        tickTask = nil
        eventsTask?.cancel()
        eventsTask = nil
        session?.delegate = nil
        session?.invalidate()
        session = nil
        peerToken = nil
        lastRunAt = nil
        let channel = self.channel
        Task { await channel.close() }
        core.stop()
        publish()
    }

    // MARK: - Transport

    private func announce(_ announcement: ProximityAnnouncement) {
        let channel = self.channel
        Task { [weak self] in
            do {
                try await channel.publish(announcement)
            } catch {
                guard let self else { return }
                self.core.channelFailed()
                self.publish()
            }
        }
    }

    private func listenToChannel() {
        eventsTask?.cancel()
        let channel = self.channel
        eventsTask = Task { [weak self] in
            let stream = await channel.events()
            for await event in stream {
                guard let self, !Task.isCancelled else { return }
                self.handle(event)
            }
        }
    }

    private func handle(_ event: ProximityPeerEvent) {
        switch event {
        case .token(let data):
            // A token we cannot decode is a fact about the payload: `.invalidToken`.
            guard let token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data) else {
                core.fail(.invalidToken)
                break
            }
            run(with: token, isRetry: false)
        case .peerCannotRange:
            core.peerCannotRange()
        case .peerLeft:
            core.peerLeft()
        case .channelFailed:
            core.channelFailed()
        }
        publish()
    }

    // MARK: - Session

    private func run(with token: NIDiscoveryToken, isRetry: Bool) {
        guard let session else { return }
        // A peer that restarts publishes a NEW token and the old one is dead,
        // so a different token is a reconnection, not a duplicate to drop.
        if !isRetry, token == peerToken { return }
        peerToken = token
        lastRunAt = Date()
        core.adoptPeerCapability(ProximityCapability(token.deviceCapabilities))
        guard core.capability != .cannotRange else {
            publish()
            return
        }
        let configuration = NINearbyPeerConfiguration(peerToken: token)
        // Extends the range at which DISTANCE survives — which is exactly the
        // regime where there is no arrow anyway, and a club floor is bigger
        // than the arrow's envelope. Apple requires checking both sides.
        configuration.isExtendedDistanceMeasurementEnabled =
            NISession.deviceCapabilities.supportsExtendedDistanceMeasurement
            && token.deviceCapabilities.supportsExtendedDistanceMeasurement
        // A retry keeps whatever the core is already saying (usually
        // `.signalLost`): a reading earns "acquiring", an API call does not.
        if !isRetry { core.peerJoined() }
        session.run(configuration)
        startTicking()
        publish()
    }

    private func retryPeer() {
        let wait = max(0, Self.minimumRerunInterval - Date().timeIntervalSince(lastRunAt ?? .distantPast))
        Task { [weak self] in
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard let self, self.isRunning, let token = self.peerToken else { return }
            self.run(with: token, isRetry: true)
        }
    }

    private func startTicking() {
        guard tickTask == nil else { return }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.tickInterval)
                guard !Task.isCancelled, let self else { return }
                self.core.tick(now: Date())
                self.publish()
                // Nothing a clock can change from here; stop burning wakeups
                // in a pocket. `run(_:)` restarts it if they come back.
                if self.state.isSettled { self.tickTask = nil; return }
            }
        }
    }

    private func publish() {
        if state != core.state { state = core.state }
    }

    // MARK: - NISessionDelegate (nonisolated; hop, never assume — see `start`)

    /// Runs `body` on the main actor without ever trapping: inline when the
    /// callback already arrived on main, enqueued otherwise.
    nonisolated private func onMain(_ body: @escaping @MainActor @Sendable () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(body)
        } else {
            Task { @MainActor in body() }
        }
    }

    nonisolated func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        let now = Date()
        let samples = nearbyObjects.map(ProximitySample.init)
        onMain { [weak self] in
            guard let self else { return }
            for sample in samples { self.core.ingest(sample, now: now) }
            self.publish()
        }
    }

    nonisolated func session(_ session: NISession,
                             didRemove nearbyObjects: [NINearbyObject],
                             reason: NINearbyObject.RemovalReason) {
        let isPeerEnded = reason == .peerEnded
        onMain { [weak self] in
            guard let self else { return }
            if isPeerEnded {
                self.core.peerLeft()
            } else {
                // NearbyInteraction gave up on the radio link. They may well
                // still be standing there, so: "lost", not "gone" — and try
                // to re-establish rather than making the user restart.
                self.core.signalTimedOut(now: Date())
                self.retryPeer()
            }
            self.publish()
        }
    }

    nonisolated func sessionWasSuspended(_ session: NISession) {
        onMain { [weak self] in
            guard let self else { return }
            self.core.suspend()
            self.publish()
        }
    }

    nonisolated func sessionSuspensionEnded(_ session: NISession) {
        onMain { [weak self] in
            guard let self else { return }
            self.core.resume()
            self.publish()
            // Apple: a suspended session resumes only by running it again.
            self.retryPeer()
        }
    }

    nonisolated func session(_ session: NISession, didInvalidateWith error: any Error) {
        let invalidation = ProximityInvalidation(error)
        onMain { [weak self] in
            guard let self else { return }
            // Apple: discard every reference to an invalidated session.
            self.session?.delegate = nil
            self.session = nil
            switch invalidation {
            case .permissionDenied: self.core.permissionDenied()
            case .platformUnsupported: self.core.platformUnsupported()
            case .fatal(let failure): self.core.fail(failure)
            }
            self.publish()
        }
    }

    private nonisolated static var hasUsageDescription: Bool {
        Bundle.main.object(forInfoDictionaryKey: "NSNearbyInteractionUsageDescription") != nil
    }
}
