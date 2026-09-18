import SwiftUI

// Las piezas de FindMyGroupView. Viven aparte porque la pantalla pasaba de
// 300 líneas, y porque todo lo de acá es PURAMENTE presentacional: recibe
// valores y devuelve closures, no toca red ni el store. Esa separación es la
// que permite mirar un estado raro (audiencia vacía, beacon resuelto, cero
// respuestas, dos personas con la misma señal) sin reproducirlo contra el
// servidor.

// MARK: - Tiempo

/// "hace 3 min" / "12 min" en tres idiomas, sin `RelativeDateTimeFormatter`
/// —que se ata al idioma del SISTEMA, no al que el usuario eligió en la app—
/// y sin instanciar un formateador por fila. Mismo criterio que `StoryTime`.
@MainActor
enum BeaconClock {
    /// Lo que queda. Nunca "0 min": por debajo del minuto decimos que queda
    /// menos de uno, porque un contador en cero al lado de una señal que
    /// sigue encendida se lee como un bug.
    static func remaining(_ seconds: TimeInterval, _ l10n: L10n) -> String {
        let minutes = Int(seconds / 60)
        return minutes < 1
            ? l10n.t("safety.time.underMinute")
            : String(format: l10n.t("safety.time.minutes"), minutes)
    }

    static func age(_ date: Date, now: Date, _ l10n: L10n) -> String {
        let seconds = max(now.timeIntervalSince(date), 0)
        if seconds < 60 { return l10n.t("story.ago.now") }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return String(format: l10n.t("story.ago.minutes"), minutes) }
        return String(format: l10n.t("story.ago.hours"), minutes / 60)
    }
}

// MARK: - Respuestas

@MainActor
enum BeaconAck {
    /// Con veinte respuestas la lista de nombres tapa la tarjeta entera.
    static let nameLimit = 4

    /// Quién CONTESTÓ — nunca quién lo vio: sin push no hay acuse de entrega,
    /// así que ese dato no existe. `nil` significa que todavía nadie.
    static func summary(_ beacon: SafetyBeacon, _ l10n: L10n) -> String? {
        guard beacon.ackCount > 0 else { return nil }
        guard !beacon.ackNames.isEmpty else {
            return String(format: l10n.t("safety.ack.anonymousCount"), beacon.ackCount)
        }
        var parts = Array(beacon.ackNames.prefix(nameLimit))
        let rest = beacon.ackCount - parts.count
        if rest > 0 { parts.append(String(format: l10n.t("safety.ack.andMore"), rest)) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Señal

/// El color Y su nombre escrito al lado. Nunca el color solo: las luces del
/// lugar corrompen el tono, y para un dicrómata dos de los cuatro colapsan.
/// El nombre es además lo único que se puede GRITAR o mandar por chat.
struct BeaconSignalChip: View {
    let signal: BeaconSignal
    /// Cuándo nació el beacon. La muestra se ancla acá y no a cuándo se montó
    /// esta vista, así late en fase con el teléfono que de verdad emite.
    let anchor: Date
    /// Falso NO es "sin ritmo": el ritmo sigue escrito al lado. Es un punto
    /// quieto, y con muchas filas vivas es lo que salva los cuadros.
    var isAnimated = true

    @ObservedObject private var l10n = L10n.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var label: String {
        "\(l10n.t(signal.colorNameKey)) · \(l10n.t(signal.rhythmNameKey))"
    }

    var body: some View {
        HStack(spacing: BPSpacing.sm) {
            swatch
            Text(label)
                .font(.bpScaled(12, weight: .heavy))
                .foregroundStyle(Color.bpInk)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.bpSurface, in: Capsule())
        .overlay(Capsule().strokeBorder(signal.color.color.opacity(0.45)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    @ViewBuilder private var swatch: some View {
        if isAnimated, !reduceMotion {
            // Muestreo a ~11 Hz: la fase más corta de los ritmos es de 180 ms
            // y por debajo de ~90 ms de muestreo el destello se pierde.
            // Deliberadamente NO es `.animation`, que redibujaría a la tasa de
            // refresco de la pantalla una vez por cada fila de la lista.
            TimelineView(.periodic(from: anchor, by: 0.09)) { context in
                dot(lit: signal.rhythm.isLit(atSecondsSinceStart: context.date.timeIntervalSince(anchor)))
            }
        } else {
            dot(lit: true)
        }
    }

    private func dot(lit: Bool) -> some View {
        Circle()
            .fill(signal.color.color)
            .frame(width: 14, height: 14)
            .opacity(lit ? 1 : 0.18)
            .shadow(color: signal.color.color.opacity(lit ? 0.7 : 0), radius: 6)
    }
}

// MARK: - Beacon ajeno

/// Alguien de tu gente levantó la mano. Los hechos, la advertencia si la
/// señal está repetida, y dos caminos.
struct IncomingBeaconRow: View {
    let entry: BeaconFeedEntry
    let now: Date
    /// El acuse de ESTA fila está en vuelo. Por fila y no global: responderle
    /// a uno no puede dejar muertos los botones de los otros once.
    let isAcking: Bool
    let onAcknowledge: () -> Void
    /// El radar trae su propio `NavigationStack`, así que lo presenta el
    /// padre en sheet. La fila sólo dice que se lo pidieron.
    let onFind: () -> Void

    @ObservedObject private var l10n = L10n.shared

    private var beacon: SafetyBeacon { entry.beacon }

    /// `placeIsKnown == false` es "no lo sabemos", jamás "en ningún lado".
    /// Un venueId sin nombre cae en la misma frase a propósito: para quien
    /// lee, un id no es un lugar.
    private var place: String {
        guard beacon.placeIsKnown, let name = beacon.venueName, !name.isEmpty else {
            return l10n.t("safety.place.unknown")
        }
        return name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BPSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text(beacon.name)
                    .font(.bpScaled(17, weight: .black, design: .rounded))
                    .foregroundStyle(Color.bpInk)
                Spacer(minLength: BPSpacing.sm)
                statusBadge
            }
            BeaconSignalChip(signal: entry.signal, anchor: beacon.createdAt,
                             isAnimated: entry.animatesSwatch)
            ambiguityNote
            if let note = beacon.note, !note.isEmpty {
                Text(note)
                    .font(.bpScaled(14))
                    .foregroundStyle(Color.bpInk.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(BPSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.bpSurface, in: RoundedRectangle(cornerRadius: BPRadius.sm))
            }
            facts
            onTheirWay
            if !beacon.isResolved { actions }
        }
        .padding(BPSpacing.md)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: BPRadius.xl)
                .strokeBorder(beacon.isResolved ? Color.bpBorder : entry.signal.color.color.opacity(0.35))
        )
    }

    private var statusBadge: some View {
        Text(beacon.isResolved
             ? l10n.t("safety.beacon.found")
             : String(format: l10n.t("safety.beacon.expiresIn"), BeaconClock.remaining(beacon.secondsRemaining, l10n)))
            .font(.bpScaled(11, weight: .heavy))
            .foregroundStyle(beacon.isResolved ? Color.bpGreen : Color.bpTextSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.bpSurface, in: Capsule())
    }

    /// El techo de cuatro colores, dicho en la fila donde importa. Sin esto
    /// el color miente con total seguridad y alguien cruza el salón al pedo.
    @ViewBuilder private var ambiguityNote: some View {
        if entry.signalIsAmbiguous {
            Label(l10n.t("safety.incoming.ambiguous"), systemImage: "exclamationmark.2")
                .font(.bpScaled(11, weight: .semibold))
                .foregroundStyle(Color.bpAmber)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var facts: some View {
        HStack(spacing: BPSpacing.sm) {
            Label(place, systemImage: beacon.placeIsKnown ? "mappin.circle.fill" : "questionmark.circle")
            Text("·")
            Text(BeaconClock.age(beacon.createdAt, now: now, l10n))
        }
        .font(.bpScaled(12))
        .foregroundStyle(Color.bpTextSecondary)
        .lineLimit(2)
    }

    /// Quiénes ya contestaron. Con doce amigos adentro esto es lo que evita
    /// que los doce crucen el salón para la misma persona.
    @ViewBuilder private var onTheirWay: some View {
        if let summary = BeaconAck.summary(beacon, l10n) {
            Label(String(format: l10n.t("safety.incoming.onTheirWay"), summary),
                  systemImage: "figure.walk.motion")
                .font(.bpScaled(12, weight: .semibold))
                .foregroundStyle(Color.bpGreen)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        HStack(spacing: BPSpacing.sm) {
            Button(action: onAcknowledge) {
                Group {
                    if isAcking {
                        ProgressView().tint(.black)
                    } else {
                        Label(l10n.t("safety.ack.onMyWay"),
                              systemImage: entry.iAmOnMyWay ? "checkmark.circle.fill" : "figure.walk")
                    }
                }
                .font(.bpScaled(13, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(entry.iAmOnMyWay ? Color.bpGreen.opacity(0.18) : Color.bpAmber,
                            in: RoundedRectangle(cornerRadius: BPRadius.md))
                .foregroundStyle(entry.iAmOnMyWay ? Color.bpGreen : Color.black)
            }
            .buttonStyle(.plain)
            .disabled(entry.iAmOnMyWay || isAcking)
            .bpAccessibility(label: l10n.t("safety.ack.onMyWay"), isButton: true)

            Button(action: onFind) {
                Label(l10n.t("safety.action.goToThem"), systemImage: "location.north.line.fill")
                    .font(.bpScaled(13, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.bpSurface, in: RoundedRectangle(cornerRadius: BPRadius.md))
                    .foregroundStyle(Color.bpInk)
            }
            .buttonStyle(.plain)
            .bpAccessibility(label: l10n.t("safety.action.goToThem"), isButton: true)
        }
    }
}
