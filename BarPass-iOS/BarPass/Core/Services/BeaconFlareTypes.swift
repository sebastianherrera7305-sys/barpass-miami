import AVFoundation
import UIKit

// MARK: - Pattern

/// A repeating on/off sequence in milliseconds, always starting with ON.
/// Piece 1 owns the catalog of patterns; this type is only the shape the
/// hardware layer can execute, plus the clamps the hardware imposes.
struct FlarePattern: Sendable, Equatable {
    struct Step: Sendable, Equatable {
        let isOn: Bool
        let milliseconds: Int
    }

    private(set) var steps: [Step]
    /// True when the requested pattern had to be altered to be executable.
    /// Surfaced rather than swallowed: a caller that asked for a 40ms strobe
    /// and silently got a 180ms one would be debugging a lie.
    private(set) var wasClamped: Bool

    /// 180ms is not a hardware limit, it is a seizure limit. Flashes above
    /// ~3 per second are the photosensitive-epilepsy risk band (WCAG 2.3.1
    /// draws its general threshold at 3 flashes/sec). A 180ms floor caps an
    /// on/off cycle at 360ms — 2.8 flashes/sec — just under it. A beacon is
    /// pointed at strangers in a dark room who never consented to a strobe.
    static let minimumStepMilliseconds = 180
    /// Beyond 10s a "pulse" is just a torch that is on, and the duty-cycle
    /// math behind the session cap stops holding.
    static let maximumStepMilliseconds = 10_000
    static let maximumSteps = 32

    /// `raw` alternates on, off, on, off… Values ≤ 0 are dropped (a zero-length
    /// step is not a step); a trailing ON with no OFF after it would fuse the
    /// cycle into a solid beam, so it gets an OFF of equal length appended.
    init(millisecondsAlternatingFromOn raw: [Int]) {
        var clamped = false
        var out: [Step] = []
        for (index, value) in raw.enumerated() {
            guard value > 0 else { clamped = true; continue }
            let ms = min(max(value, Self.minimumStepMilliseconds), Self.maximumStepMilliseconds)
            if ms != value { clamped = true }
            out.append(Step(isOn: out.count % 2 == 0, milliseconds: ms))
            if out.count >= Self.maximumSteps && index < raw.count - 1 { clamped = true; break }
        }
        if out.isEmpty {
            out = Self.steadySteps
            clamped = true
        } else if out.count % 2 == 1 {
            out.append(Step(isOn: false, milliseconds: out[out.count - 1].milliseconds))
            clamped = true
        }
        steps = out
        wasClamped = clamped
    }

    private static let steadySteps = [Step(isOn: true, milliseconds: 900), Step(isOn: false, milliseconds: 600)]

    var cycleMilliseconds: Int { steps.reduce(0) { $0 + $1.milliseconds } }
    /// Fraction of the cycle the torch is lit. The session cap assumes this
    /// stays well under 1.0; a caller can read it to show expected drain.
    var dutyCycle: Double {
        let total = cycleMilliseconds
        guard total > 0 else { return 0 }
        return Double(steps.filter(\.isOn).reduce(0) { $0 + $1.milliseconds }) / Double(total)
    }

    static let steady = FlarePattern(millisecondsAlternatingFromOn: [900, 600])

    /// Un único paso ENCENDIDO, sin apagado detrás: el haz queda fijo.
    ///
    /// No sale del init público a propósito — ese init le agrega un OFF a
    /// cualquier secuencia impar, que es justo lo que rompe un ritmo
    /// continuo: la pantalla se queda fija y la linterna parpadea, y de
    /// lejos eso lee como un ritmo distinto que no es de nadie. El haz fijo
    /// es el patrón más caro en batería y calor que puede pedir esta capa;
    /// lo sostienen el tope de sesión y la mitigación térmica, no la suerte.
    static let continuousBeam: FlarePattern = {
        var pattern = FlarePattern(millisecondsAlternatingFromOn: [maximumStepMilliseconds])
        pattern.steps = [Step(isOn: true, milliseconds: maximumStepMilliseconds)]
        pattern.wasClamped = false
        return pattern
    }()
}

// MARK: - Honest states

/// Why the flare is weaker than the user asked for. Never collapsed into one
/// "unavailable" case: each of these needs a different sentence on screen,
/// and one of them explicitly means we do not know.
enum FlareLimit: Sendable, Equatable {
    /// iPad, iPod, some SE bodies in some markets. The screen is still a beacon.
    case noTorchHardware
    /// `lockForConfiguration()` threw — another process holds the capture
    /// device. This is the only case where "another app has the camera" is
    /// a fact and not a guess.
    case cameraBusy
    /// The torch exists, nothing is overheating, and AVFoundation still
    /// reports it unavailable. We do not know why, and we say so.
    case torchUnavailableUnknownReason
    case overheating(ProcessInfo.ThermalState)
    case batteryLow(Float)
    case batteryCritical(Float)
}

/// iOS returns -1 for `batteryLevel` until monitoring has warmed up, and on
/// some simulators forever. -1 is not 0%; treating it as empty would shut the
/// beacon off on a full phone.
enum BatteryReading: Sendable, Equatable {
    case unknown
    case known(Float)

    /// `@MainActor` because `UIDevice.current` is — the same class of implicit
    /// hop that crashed builds 22/26/50.
    @MainActor static func read() -> BatteryReading {
        let level = UIDevice.current.batteryLevel
        return level < 0 ? .unknown : .known(level)
    }
}

enum TorchStatus: Sendable, Equatable {
    case pulsing(level: Float)
    case dimmed(level: Float, because: FlareLimit)
    case off(because: FlareLimit)
    case pausedOutsideForeground
}

enum ScreenStatus: Sendable, Equatable {
    case boosted(Double)
    case held(Double, because: FlareLimit)
    case restored
}

enum BeaconFlareState: Sendable, Equatable {
    case idle
    case active(torch: TorchStatus, screen: ScreenStatus, battery: BatteryReading, endsAt: Date)
    /// A call, the app switcher, Control Center, or the side button. The torch
    /// is off and the brightness is back — see `honestLimits`.
    case pausedOutsideForeground(endsAt: Date)
    /// The session cap ran out. Only an explicit `renew()` restarts it.
    case expired
}

// MARK: - Policy (pure, testable without hardware)

enum FlareMitigation: Sendable, Equatable {
    case none
    case reduce(FlareLimit)
    case torchOff(FlareLimit)
    case minimal(FlareLimit)

    var rank: Int {
        switch self {
        case .none: return 0
        case .reduce: return 1
        case .torchOff: return 2
        case .minimal: return 3
        }
    }
}

enum FlarePolicy {
    static let reducedTorchLevel: Float = 0.35
    static let fullScreen = 1.0
    static let reducedScreen = 0.65
    /// Below this the torch is refused: the person who is lost still needs a
    /// phone that can place a call, and the torch is the single largest
    /// controllable draw on the device.
    static let torchBatteryFloor: Float = 0.15
    static let screenBatteryFloor: Float = 0.05

    /// 10 minutes. A beacon answers "I am the one waving, come here" — a
    /// friend crossing a room, a driver scanning a line of cars. That is a
    /// minutes-long problem. Long enough that nobody renews while someone is
    /// walking toward them; short enough that a phone left flaring in a
    /// pocket costs a few percent instead of the night. Renewal is a tap,
    /// which is the one thing a forgotten phone cannot produce.
    static let maxSessionSeconds: TimeInterval = 600

    static func mitigation(thermal: ProcessInfo.ThermalState, battery: BatteryReading) -> FlareMitigation {
        var worst = FlareMitigation.none
        func consider(_ candidate: FlareMitigation) {
            if candidate.rank > worst.rank { worst = candidate }
        }
        switch thermal {
        // Act before iOS does. At .critical iOS kills the torch itself and
        // the user sees a beacon that "broke"; at .serious it starts
        // throttling. Stepping down first means we can explain it.
        case .serious: consider(.reduce(.overheating(.serious)))
        case .critical: consider(.minimal(.overheating(.critical)))
        default: break
        }
        if case .known(let level) = battery {
            if level <= screenBatteryFloor {
                consider(.minimal(.batteryCritical(level)))
            } else if level <= torchBatteryFloor {
                consider(.torchOff(.batteryLow(level)))
            }
        }
        return worst
    }

    static func torchStatus(_ mitigation: FlareMitigation, hardware: FlareLimit?) -> TorchStatus {
        if let hardware { return .off(because: hardware) }
        switch mitigation {
        case .none: return .pulsing(level: AVCaptureDevice.maxAvailableTorchLevel)
        case .reduce(let limit): return .dimmed(level: reducedTorchLevel, because: limit)
        case .torchOff(let limit), .minimal(let limit): return .off(because: limit)
        }
    }

    static func screenStatus(_ mitigation: FlareMitigation) -> ScreenStatus {
        if case .minimal(let limit) = mitigation { return .held(reducedScreen, because: limit) }
        return .boosted(fullScreen)
    }
}

// MARK: - Brightness vault

/// The saved brightness lives in UserDefaults, not in a property, so that a
/// crash or a force-quit while the beacon is lit does not strand the user at
/// 100% forever — the next launch finds the key and puts it back.
@MainActor
enum BrightnessVault {
    private static let key = "bp_beacon_saved_brightness"
    private static let idleKey = "bp_beacon_saved_idle_timer"

    /// Never overwrites an existing saved value. Capturing twice is how a
    /// beacon restarted while already lit would "restore" the user to 1.0.
    static func capture() {
        guard UserDefaults.standard.object(forKey: key) == nil else { return }
        UserDefaults.standard.set(Double(UIScreen.main.brightness), forKey: key)
        UserDefaults.standard.set(UIApplication.shared.isIdleTimerDisabled, forKey: idleKey)
    }

    static func apply(_ value: Double) {
        UIScreen.main.brightness = CGFloat(value)
        UIApplication.shared.isIdleTimerDisabled = true
    }

    @discardableResult
    static func restore() -> Double? {
        guard let saved = UserDefaults.standard.object(forKey: key) as? Double else { return nil }
        UIScreen.main.brightness = CGFloat(saved)
        UIApplication.shared.isIdleTimerDisabled = UserDefaults.standard.bool(forKey: idleKey)
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: idleKey)
        return saved
    }

    static var holdsValue: Bool { UserDefaults.standard.object(forKey: key) != nil }
}

