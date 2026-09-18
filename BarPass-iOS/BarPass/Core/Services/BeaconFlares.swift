import AVFoundation
import Combine
import UIKit

// MARK: - Service

/// Drives the two pieces of hardware a phone can use to be seen from far
/// away: the screen and the torch.
///
/// Isolation follows `LocationService` exactly — `@MainActor` class, system
/// callbacks `nonisolated` and hopping through `onMain`. Builds 22/26/50 died
/// of a background-queue callback entering main-actor state, and
/// `thermalStateDidChangeNotification` posts on an arbitrary queue: same trap.
@MainActor
final class BeaconFlares: ObservableObject {
    /// Screen and torch are one shared resource; two instances fighting over
    /// them is how a user ends up at 100% brightness forever.
    static let shared = BeaconFlares()

    @Published private(set) var state: BeaconFlareState = .idle

    private var pattern: FlarePattern = .steady
    /// El instante del que derivan TANTO la pantalla como la linterna. Sin
    /// esto cada capa corría su propio reloj: `Task.sleep` garantiza "al
    /// menos" N ms, nunca exactamente N, así que el error se acumula y a los
    /// dos minutos la linterna va media fase corrida respecto de la pantalla.
    /// Visto de lejos eso no es un detalle estético — es un QUINTO ritmo que
    /// no le pertenece a nadie.
    private(set) var anchor = Date()
    private var pulseTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    private var endsAt: Date?
    private var observers: [NSObjectProtocol] = []
    private var previousBatteryMonitoring = false

    /// Read by the pulse loop at every step, so a thermal or battery change
    /// takes effect within one flash without tearing the loop down.
    private var torchLevel: Float = AVCaptureDevice.maxAvailableTorchLevel
    private var torchAllowed = false

    /// True while THIS instance holds the hardware. Every acquire/release goes
    /// through `acquireHold`/`releaseHold`: a drifted counter means the saved
    /// brightness is never handed back. It also gates `evaluate()`, so a stray
    /// thermal notification cannot relight a beacon the user never renewed.
    private var isHolding = false
    private static var activeSessions = 0

    private var torchDevice: AVCaptureDevice? { AVCaptureDevice.default(for: .video) }

    // MARK: Public API

    /// Starts or restarts a session. Never throws: no torch, a busy camera and
    /// an overheating phone are things the user must be TOLD, not errors that
    /// take the screen beacon down too. Calling it twice re-applies the pattern
    /// without taking a second hold.
    func start(pattern: FlarePattern, anchoredAt anchor: Date = Date()) {
        self.pattern = pattern
        self.anchor = anchor
        if endsAt == nil || state == .expired { endsAt = Date().addingTimeInterval(FlarePolicy.maxSessionSeconds) }
        installObservers()
        UIDevice.current.isBatteryMonitoringEnabled = true
        acquireHold()
        evaluate()
        scheduleExpiry()
    }

    /// Explicit user renewal, re-running every safety gate: a phone that got
    /// hot or drained in the first ten minutes does not get the same beacon.
    func renew() {
        endsAt = Date().addingTimeInterval(FlarePolicy.maxSessionSeconds)
        guard isHolding else { start(pattern: pattern); return }
        evaluate()
        scheduleExpiry()
    }

    func stop() {
        pulseTask?.cancel(); pulseTask = nil
        expiryTask?.cancel(); expiryTask = nil
        endsAt = nil
        torchAllowed = false
        Self.setTorch(on: false, level: torchLevel)
        releaseHold()
        // Only if we turned it on: don't switch off someone else's monitoring.
        if !observers.isEmpty { UIDevice.current.isBatteryMonitoringEnabled = previousBatteryMonitoring }
        removeObservers()
        state = .idle
    }

    /// Call once at launch from the AppDelegate: if a previous run was
    /// force-quit or crashed while lit, the saved brightness is still in
    /// UserDefaults and this is what hands it back.
    static func restoreOrphanedBrightness() {
        guard activeSessions == 0, BrightnessVault.holdsValue else { return }
        BrightnessVault.restore()
        emergencyTorchOff()
    }

    /// Synchronous and callable from anywhere, `deinit` included. The torch is
    /// the one thing that must never outlive the object that lit it.
    nonisolated static func emergencyTorchOff() { setTorch(on: false, level: 1.0) }

    deinit {
        // A view torn down mid-flare lands here. Torch dies synchronously; the
        // brightness needs main, so the hold is released there. Reading
        // `isHolding` is safe: deinit has exclusive access.
        Self.emergencyTorchOff()
        guard isHolding else { return }
        Task { @MainActor in BeaconFlares.releaseOrphanedHold() }
    }

    /// Releases a hold whose owner is gone. Separate from
    /// `restoreOrphanedBrightness()`, which handles a *previous process*.
    private static func releaseOrphanedHold() {
        guard activeSessions > 0 else { return }
        activeSessions -= 1
        if activeSessions == 0 { BrightnessVault.restore() }
    }

    // MARK: Hold accounting

    private func acquireHold() {
        guard !isHolding else { return }
        isHolding = true
        if Self.activeSessions == 0 { BrightnessVault.capture() }
        Self.activeSessions += 1
    }

    private func releaseHold() {
        guard isHolding else { return }
        isHolding = false
        Self.activeSessions -= 1
        if Self.activeSessions == 0 { BrightnessVault.restore() }
    }

    // MARK: Evaluation

    private func evaluate() {
        guard isHolding, let endsAt else { return }
        let battery = BatteryReading.read()
        let mitigation = FlarePolicy.mitigation(thermal: ProcessInfo.processInfo.thermalState, battery: battery)
        let torch = FlarePolicy.torchStatus(mitigation, hardware: hardwareLimit())
        let screen = FlarePolicy.screenStatus(mitigation)

        switch torch {
        case .pulsing(let level), .dimmed(let level, _): torchLevel = level; torchAllowed = true
        case .off, .pausedOutsideForeground:
            torchAllowed = false
            Self.setTorch(on: false, level: torchLevel)
        }
        switch screen {
        // Re-applied every cycle: auto-brightness drifts the panel back down,
        // and a beacon that fades while someone walks toward it is worse than
        // one that never lit.
        case .boosted(let value), .held(let value, _): BrightnessVault.apply(value)
        case .restored: BrightnessVault.restore()
        }
        state = .active(torch: torch, screen: screen, battery: battery, endsAt: endsAt)
        syncPulse()
    }

    /// Checked in order of how certain we are: `hasTorch` is a device fact, a
    /// throwing lock is proof another process holds the capture device, and
    /// anything else leaving `isTorchAvailable` false on a cool phone is
    /// unexplained — reported as unexplained rather than guessed at. Re-run
    /// every cycle because another app can take the camera mid-session.
    private func hardwareLimit() -> FlareLimit? {
        guard let device = torchDevice, device.hasTorch else { return .noTorchHardware }
        do {
            try device.lockForConfiguration()
            device.unlockForConfiguration()
        } catch {
            return .cameraBusy
        }
        let thermal = ProcessInfo.processInfo.thermalState
        let unexplained = !device.isTorchAvailable && thermal != .serious && thermal != .critical
        return unexplained ? .torchUnavailableUnknownReason : nil
    }

    // MARK: Pulse

    /// Runs the loop only while the torch is usable: a loop waking every 180ms
    /// to do nothing is battery spent on someone already in trouble.
    private func syncPulse() {
        if torchAllowed, pulseTask == nil { runPulse() }
        else if !torchAllowed { pulseTask?.cancel(); pulseTask = nil }
    }

    private func runPulse() {
        pulseTask?.cancel()
        pulseTask = Task { [weak self] in
            var cyclesSinceCheck = 0
            while !Task.isCancelled {
                guard let self, let steps = self.currentSteps() else { return }
                // Dónde estamos AHORA dentro del patrón, medido contra el
                // ancla — no contra cuánto durmió el loop. Si el sistema nos
                // robó 40ms, el paso siguiente dura 40ms menos y el error no
                // se arrastra: el patrón vuelve a alinearse solo.
                let (index, remaining) = Self.step(in: steps, atMillisecondsSince: self.anchor)
                self.applyStep(steps[index])
                try? await Task.sleep(for: .milliseconds(max(remaining, 1)))
                guard !Task.isCancelled else { return }
                // Re-chequear térmica y batería una vez por ciclo completo, no
                // por paso: `batteryLevelDidChange` sólo avisa en saltos de 1%
                // y con minutos de diferencia, pero un teléfono sí puede
                // cruzar a .serious entre dos destellos. `evaluate` puede
                // cancelar esta misma task — el `while` lo levanta en la
                // vuelta siguiente.
                cyclesSinceCheck += 1
                if cyclesSinceCheck >= steps.count {
                    cyclesSinceCheck = 0
                    self.evaluate()
                }
            }
        }
    }

    /// Paso activo y milisegundos que le quedan, derivados del ancla. Puro y
    /// total: un patrón de duración cero devuelve el primer paso en vez de
    /// dividir por cero, porque un faro que se apaga por un caso borde es un
    /// faro que falló.
    nonisolated static func step(in steps: [FlarePattern.Step], atMillisecondsSince anchor: Date) -> (index: Int, remaining: Int) {
        let period = steps.reduce(0) { $0 + $1.milliseconds }
        guard period > 0, !steps.isEmpty else { return (0, 180) }
        let elapsed = Date().timeIntervalSince(anchor) * 1000
        guard elapsed.isFinite, abs(elapsed) <= 9_007_199_254_740_992 else { return (0, steps[0].milliseconds) }
        var offset = Int(elapsed.truncatingRemainder(dividingBy: Double(period)))
        if offset < 0 { offset += period }
        for (index, step) in steps.enumerated() {
            if offset < step.milliseconds { return (index, step.milliseconds - offset) }
            offset -= step.milliseconds
        }
        return (0, steps[0].milliseconds)
    }

    private func currentSteps() -> [FlarePattern.Step]? {
        guard case .active = state else { return nil }
        return pattern.steps
    }

    private func applyStep(_ step: FlarePattern.Step) {
        guard torchAllowed else { return }
        Self.setTorch(on: step.isOn, level: torchLevel)
    }

    /// `lockForConfiguration` is a short, uncontended lock in a single-app
    /// process, so it runs on the main actor rather than opening a second
    /// isolation domain around a device two places must never drive at once.
    nonisolated private static func setTorch(on: Bool, level: Float) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        guard (try? device.lockForConfiguration()) != nil else { return }
        defer { device.unlockForConfiguration() }
        if on, device.isTorchAvailable {
            try? device.setTorchModeOn(level: min(max(level, 0.01), AVCaptureDevice.maxAvailableTorchLevel))
        } else {
            device.torchMode = .off
        }
    }

    // MARK: Session cap

    private func scheduleExpiry() {
        expiryTask?.cancel()
        guard let endsAt else { return }
        let remaining = max(endsAt.timeIntervalSinceNow, 0)
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled, let self else { return }
            self.expire()
        }
    }

    private func expire() {
        pulseTask?.cancel(); pulseTask = nil
        torchAllowed = false
        Self.setTorch(on: false, level: torchLevel)
        releaseHold()
        state = .expired
    }

    // MARK: Foreground handoff

    private func suspend() {
        guard case .active = state, let endsAt else { return }
        pulseTask?.cancel(); pulseTask = nil
        torchAllowed = false
        // Our loop stops running once we lose the foreground; leaving the torch
        // as the last step set it would burn it solid against a suspended timer
        // — the exact drain this service exists to prevent.
        Self.setTorch(on: false, level: torchLevel)
        releaseHold()
        state = .pausedOutsideForeground(endsAt: endsAt)
    }

    private func resume() {
        guard case .pausedOutsideForeground = state, let endsAt else { return }
        guard endsAt > Date() else { expire(); return }
        acquireHold()
        evaluate()
        scheduleExpiry()
    }

    // MARK: Observers

    private func installObservers() {
        guard observers.isEmpty else { return }
        previousBatteryMonitoring = UIDevice.current.isBatteryMonitoringEnabled
        let center = NotificationCenter.default
        func observe(_ name: Notification.Name, _ body: @escaping @MainActor (BeaconFlares) -> Void) {
            observers.append(center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                BeaconFlares.onMain { guard let self else { return }; body(self) }
            })
        }
        observe(UIApplication.willResignActiveNotification) { $0.suspend() }
        observe(UIApplication.didBecomeActiveNotification) { $0.resume() }
        observe(ProcessInfo.thermalStateDidChangeNotification) { $0.evaluate() }
        observe(UIDevice.batteryLevelDidChangeNotification) { $0.evaluate() }
        observe(UIDevice.batteryStateDidChangeNotification) { $0.evaluate() }
    }

    private func removeObservers() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }

    /// Identical to `LocationService.onMain`: never traps, runs inline when
    /// the callback already arrived on main and enqueues when it did not.
    nonisolated private static func onMain(_ body: @escaping @MainActor @Sendable () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(body)
        } else {
            Task { @MainActor in body() }
        }
    }
}
