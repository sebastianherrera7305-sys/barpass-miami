import SwiftUI

/// El camino que funciona en TODOS los teléfonos: el color y el ritmo.
///
/// Existe como pieza propia porque el radar la usa de dos maneras distintas y
/// ninguna es decorativa:
///  · de HÉROE, cuando `state.shouldFallBackToBeacon` — un iPhone SE sin
///    antena, un permiso denegado, una sesión que falló, o la llegada. Ahí el
///    color no es un consuelo, es la respuesta.
///  · de TIRA al pie mientras el radar sí funciona, para que nadie tenga que
///    descubrir que existía recién cuando el radar se rompe.
///
/// El disco parpadea en FASE con el teléfono real: las dos pantallas derivan el
/// instante encendido de `beacon.createdAt`, el mismo ancla que usa
/// `BeaconFlares`. Sin ese ancla compartido, la vista previa late por su cuenta
/// y enseña un ritmo corrido respecto del que hay que buscar al otro lado del
/// salón. El ritmo ya viene acotado a ≤3 destellos por segundo (WCAG 2.3.1) por
/// `BeaconRhythm`, así que esta vista no tiene que volver a limitarlo — pero sí
/// respeta Reduce Motion, que es una preferencia distinta de la fotosensible.
struct ProximityRadarFallbackCard: View {
    let beacon: SafetyBeacon
    let signal: BeaconSignal
    /// Compacto = la tira al pie. Completo = el héroe.
    var isCompact: Bool = false

    @ObservedObject private var l10n = L10n.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var discSize: CGFloat { isCompact ? 54 : 128 }

    var body: some View {
        HStack(alignment: .center, spacing: BPSpacing.md) {
            if isCompact { disc }
            VStack(alignment: isCompact ? .leading : .center, spacing: BPSpacing.sm) {
                if !isCompact { disc.padding(.bottom, BPSpacing.xs) }
                Text(sentence)
                    .font(isCompact ? .bpCaption() : .bpTitle2())
                    .foregroundStyle(Color.bpInk)
                    .multilineTextAlignment(isCompact ? .leading : .center)
                Text(l10n.t("radar.fallback.why"))
                    .font(.bpSmall())
                    .foregroundStyle(Color.bpTextSecondary)
                    .multilineTextAlignment(isCompact ? .leading : .center)
            }
            .frame(maxWidth: .infinity, alignment: isCompact ? .leading : .center)
        }
        .padding(isCompact ? BPSpacing.md : BPSpacing.lg)
        .frame(maxWidth: .infinity)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.lg).strokeBorder(Color.bpBorder))
        .accessibilityElement(children: .ignore)
        .bpAccessibility(label: "\(sentence) \(l10n.t("radar.fallback.why"))")
    }

    // MARK: - El disco

    /// Fondo casi negro siempre, en tema claro también: lo que hay que
    /// reconocer del otro lado del salón es una pantalla ENCENDIDA en la
    /// oscuridad, y un dorado sobre blanco no se parece a eso.
    private var disc: some View {
        ZStack {
            RoundedRectangle(cornerRadius: BPRadius.md)
                .fill(Color.black.opacity(0.92))
            if reduceMotion {
                // Sin parpadeo el color sigue siendo correcto; el ritmo lo
                // lleva el texto, que es la mitad de la identidad que sobrevive
                // cuando el color no se puede distinguir.
                Circle().fill(signal.color.color).padding(discSize * 0.16)
            } else {
                TimelineView(.periodic(from: beacon.createdAt, by: 0.06)) { context in
                    // 60 ms de muestreo contra una fase mínima de 180 ms: el
                    // error de fase es imperceptible y el costo es una sola
                    // figura redibujándose.
                    let elapsed = context.date.timeIntervalSince(beacon.createdAt)
                    let isLit = signal.rhythm.isLit(atSecondsSinceStart: elapsed)
                    Circle()
                        .fill(signal.color.color)
                        .padding(discSize * 0.16)
                        .opacity(isLit ? 1 : 0.06)
                        .shadow(color: signal.color.color.opacity(isLit ? 0.7 : 0), radius: 18)
                }
            }
        }
        .frame(width: discSize, height: discSize)
    }

    // MARK: - La frase

    /// El color Y el ritmo, nunca uno solo: el nombre del color es lo que se
    /// grita a través de un salón, y el ritmo es lo que le queda a alguien que
    /// no distingue los dos tonos.
    private var sentence: String {
        let color = l10n.t(signal.colorNameKey)
        let rhythm = l10n.t(signal.rhythmNameKey)
        if beacon.isMine {
            return String(format: l10n.t("safety.beacon.youAre"), color, rhythm)
        }
        return String(format: l10n.t("safety.beacon.memberIs"), beacon.name, color, rhythm)
    }
}
