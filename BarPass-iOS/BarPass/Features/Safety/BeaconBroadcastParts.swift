import SwiftUI

// La capa de TRADUCCIÓN de BeaconBroadcastView: cuándo redibujar, y cómo se
// dice en palabras cada estado del hardware. Las vistas de la placa viven en
// BeaconBroadcastPlate.swift; acá no hay ninguna decisión de layout.
//
// Está separada porque todo esto es mirable sin hardware —una cadencia que es
// aritmética y un diccionario de estados a frases— así que se puede leer qué
// dice la pantalla con el teléfono recalentado sin recalentar ninguno.

// MARK: - Cadencia de redibujo

/// Dispara EXACTAMENTE en los bordes de fase del ritmo, y nada más.
///
/// Por qué no `.animation` (60-120 Hz) ni `.periodic(by: 1/30)`: los dos
/// redibujan la pantalla entera decenas de veces por segundo para mostrar dos
/// valores, y el periódico además CUANTIZA el borde a su propio paso — con
/// fases de 180 ms, ±33 ms es un 18% de la fase, y eso se ve como un destello
/// que tiembla. Anclado a los bordes, `fastFlicker` (el más caro de los cinco
/// ritmos) cuesta 5,6 redibujos por segundo, `slowBlink` 1,4, y el borde cae
/// donde tiene que caer. Es batería de alguien que está perdido.
struct BeaconPhaseSchedule: TimelineSchedule {
    let rhythm: BeaconRhythm
    /// El mismo instante del que se deriva la linterna. No es el reloj de la
    /// verdad —la vista vuelve a leer el ancla viva en cada frame— sino el
    /// que decide CUÁNDO redibujar.
    let anchor: Date
    /// `solid` no tiene borde que dibujar. Un latido flojo mantiene la vista
    /// viva sin gastar nada.
    private static let idleTick: TimeInterval = 2

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnySequence<Date> {
        let period = TimeInterval(rhythm.periodMilliseconds) / 1000
        guard period > 0, !rhythm.isContinuous, mode == .normal else {
            return AnySequence(sequence(first: startDate.addingTimeInterval(Self.idleTick)) {
                $0.addingTimeInterval(Self.idleTick)
            })
        }
        var offsets: [TimeInterval] = []
        var cursor: TimeInterval = 0
        for phase in rhythm.phases {
            offsets.append(cursor)
            cursor += TimeInterval(phase.milliseconds) / 1000
        }
        return AnySequence { Boundaries(anchor: anchor, period: period, offsets: offsets, cursor: startDate) }
    }

    /// Estrictamente creciente por construcción: si el cursor cae justo sobre
    /// un borde devuelve el siguiente, nunca el mismo. Un iterador que repite
    /// una fecha cuelga a TimelineView.
    private struct Boundaries: IteratorProtocol {
        let anchor: Date
        let period: TimeInterval
        let offsets: [TimeInterval]
        var cursor: Date

        mutating func next() -> Date? {
            let elapsed = cursor.timeIntervalSince(anchor)
            guard elapsed.isFinite, let first = offsets.first else { return nil }
            let base = anchor.addingTimeInterval((elapsed / period).rounded(.down) * period)
            for offset in offsets {
                let candidate = base.addingTimeInterval(offset)
                if candidate > cursor { cursor = candidate; return candidate }
            }
            cursor = base.addingTimeInterval(period + first)
            return cursor
        }
    }
}

// MARK: - Estados honestos, en palabras

struct BeaconStatusLine {
    let symbol: String, text: String, tint: Color
    init(_ symbol: String, _ text: String, _ tint: Color) {
        (self.symbol, self.text, self.tint) = (symbol, text, tint)
    }
}

/// Cada límite con su frase propia. Colapsarlos en "no disponible" sería
/// mentir por omisión: no es lo mismo una linterna apagada por calor, que una
/// que otra app tiene tomada, que un teléfono que directamente no la tiene —
/// y sólo una de las tres tiene arreglo desde donde está parado el usuario.
@MainActor
enum BeaconFlareCopy {
    static func torch(_ status: TorchStatus, _ l10n: L10n) -> BeaconStatusLine {
        switch status {
        case .pulsing:
            return .init("flashlight.on.fill", l10n.t("beacon.torch.pulsing"), .bpGreen)
        case .dimmed(_, let limit):
            if case .overheating = limit {
                return .init("flashlight.on.fill", l10n.t("beacon.torch.dimmed.overheating"), .bpAmber)
            }
            // `FlarePolicy` hoy sólo atenúa por temperatura. Si mañana atenúa
            // por otra cosa, esto dice "bajamos la linterna" sin inventarle
            // una causa que no conocemos.
            return .init("flashlight.on.fill", l10n.t("beacon.torch.dimmed.other"), .bpAmber)
        case .off(let limit):
            return .init("flashlight.off.fill", torchOff(limit, l10n), .bpDanger)
        case .pausedOutsideForeground:
            return .init("pause.circle.fill", l10n.t("beacon.paused.body"), .bpAmber)
        }
    }

    private static func torchOff(_ limit: FlareLimit, _ l10n: L10n) -> String {
        switch limit {
        case .noTorchHardware: return l10n.t("beacon.torch.off.noHardware")
        case .cameraBusy: return l10n.t("beacon.torch.off.cameraBusy")
        case .torchUnavailableUnknownReason: return l10n.t("beacon.torch.off.unknown")
        case .overheating: return l10n.t("beacon.torch.off.overheating")
        case .batteryLow(let level):
            return String(format: l10n.t("beacon.torch.off.batteryLow"), percent(level))
        case .batteryCritical(let level):
            return String(format: l10n.t("beacon.torch.off.batteryCritical"), percent(level))
        }
    }

    static func screen(_ status: ScreenStatus, _ l10n: L10n) -> BeaconStatusLine {
        switch status {
        case .boosted: return .init("sun.max.fill", l10n.t("beacon.screen.boosted"), .bpGreen)
        case .held: return .init("sun.min.fill", l10n.t("beacon.screen.reduced"), .bpAmber)
        case .restored: return .init("sun.min.fill", l10n.t("beacon.screen.restored"), .white.opacity(0.6))
        }
    }

    /// -1 no es 0%: iOS devuelve eso hasta que el monitoreo arranca, y en
    /// algún simulador para siempre. "No sabemos" es un dato, no un hueco.
    static func battery(_ reading: BatteryReading, _ l10n: L10n) -> BeaconStatusLine {
        switch reading {
        case .unknown:
            return .init("battery.100", l10n.t("beacon.battery.unknown"), .white.opacity(0.6))
        case .known(let level):
            let low = level <= FlarePolicy.torchBatteryFloor
            return .init(low ? "battery.25" : "battery.100",
                         String(format: l10n.t("beacon.battery.level"), percent(level)),
                         low ? .bpDanger : .white.opacity(0.6))
        }
    }

    /// Título y cuerpo de una interrupción con nombre. `nil` = no hay nada que
    /// explicar. `.idle` entra acá como nil a propósito: la pantalla lo
    /// resuelve encendiendo la baliza, no describiéndolo.
    static func interrupted(_ state: BeaconFlareState) -> (title: String, body: String)? {
        switch state {
        case .expired: return ("beacon.expired.title", "beacon.expired.body")
        case .pausedOutsideForeground: return ("beacon.paused.title", "beacon.paused.body")
        case .idle, .active: return nil
        }
    }

    /// Lo que VoiceOver tiene que poder contestar: quién sos, y qué está
    /// haciendo el teléfono. Nominal alcanza la frase ya escrita; si no, se
    /// leen los hechos, en vez de prometer una linterna que está apagada.
    static func voiceOverSummary(_ state: BeaconFlareState, identity: String, _ l10n: L10n) -> String {
        guard case .active(let t, let s, _, _) = state else { return identity }
        if case .pulsing = t, case .boosted = s {
            return identity + " " + l10n.t("beacon.a11y.active")
        }
        return [identity, torch(t, l10n).text, screen(s, l10n).text].joined(separator: " ")
    }

    /// Lo que queda de la sesión de hardware. Pausada sigue corriendo: el tope
    /// es absoluto, una llamada de cinco minutos se come cinco minutos.
    static func sessionRemaining(_ state: BeaconFlareState) -> TimeInterval {
        switch state {
        case .active(_, _, _, let endsAt), .pausedOutsideForeground(let endsAt):
            return max(endsAt.timeIntervalSinceNow, 0)
        case .idle, .expired: return 0
        }
    }

    private static func percent(_ level: Float) -> Int { Int((level * 100).rounded()) }
}

struct BeaconStatusRow: View {
    let line: BeaconStatusLine

    var body: some View {
        HStack(alignment: .top, spacing: BPSpacing.sm) {
            Image(systemName: line.symbol)
                .font(.bpScaled(12, weight: .bold))
                .foregroundStyle(line.tint)
                .frame(width: 18)
            Text(line.text)
                .font(.bpScaled(12))
                // Blanco explícito, no `bpInk`: la placa es negra en los dos
                // temas (ver la cabecera de BeaconBroadcastView).
                .foregroundStyle(.white.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
