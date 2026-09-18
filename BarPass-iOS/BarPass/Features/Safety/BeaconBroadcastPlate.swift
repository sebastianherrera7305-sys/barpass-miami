import SwiftUI

// LA PLACA de BeaconBroadcastView: todo lo que se lee con el teléfono ya
// bajado. Vive aparte porque es puramente presentacional —recibe valores y
// devuelve closures, no toca red ni el store— y eso permite mirar un estado
// raro (linterna apagada por calor, cero respuestas, sesión vencida) sin
// tener que reproducirlo con hardware.
//
// Todo acá pinta blanco y negro EXPLÍCITOS en vez de `Color.bpInk`: la placa
// es negra en los dos temas porque está apoyada sobre el campo que parpadea,
// y `bpInk` se da vuelta con `AppearanceStore.isDark` — sería tinta oscura
// sobre negro. Del design system salen tipografía, espaciado y háptica.

// MARK: - Quién sos

/// La frase que se puede GRITAR, y debajo qué hacer con el teléfono.
/// La instrucción está, pero no le pelea a la identidad: 13pt contra 29pt.
struct BeaconIdentityBlock: View {
    let sentence: String
    let tint: Color

    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        HStack(alignment: .top, spacing: BPSpacing.md) {
            // Muestra fija del tono, legible de cerca también durante la fase
            // oscura. Chica y sobre negro: de lejos no compite con el campo.
            Capsule().fill(tint).frame(width: 5)
            VStack(alignment: .leading, spacing: 6) {
                Text(sentence)
                    .font(.bpScaled(29, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.55)
                    .accessibilityAddTraits(.isHeader)
                Text(l10n.t("beacon.broadcast.holdUp"))
                    .font(.bpScaled(13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Qué está haciendo el teléfono

/// Los tres hechos del hardware, cada uno con su frase propia, más las dos
/// advertencias que sólo aparecen cuando corresponden.
struct BeaconFlareStatusList: View {
    let state: BeaconFlareState
    /// El motor tuvo que alterar el patrón: la linterna y la pantalla corren
    /// ritmos distintos. Se dice, no se deja pasar.
    let patternWasAltered: Bool
    let dimFlashing: Bool

    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        VStack(alignment: .leading, spacing: BPSpacing.sm) {
            if case .active(let torch, let screen, let battery, _) = state {
                BeaconStatusRow(line: BeaconFlareCopy.torch(torch, l10n))
                BeaconStatusRow(line: BeaconFlareCopy.screen(screen, l10n))
                BeaconStatusRow(line: BeaconFlareCopy.battery(battery, l10n))
            }
            if patternWasAltered {
                BeaconStatusRow(line: .init("exclamationmark.triangle.fill",
                                            l10n.t("beacon.pattern.clamped"), .bpAmber))
            }
            if dimFlashing {
                BeaconStatusRow(line: .init("sparkles",
                                            l10n.t("beacon.broadcast.dimmedFlashes"), .bpAmber))
            }
        }
    }
}

/// Una interrupción con nombre y con salida. Devuelve vacío cuando no hay
/// nada que explicar, y sólo ofrece renovar cuando renovar es la acción — en
/// pausa el arreglo es volver a la app, y un botón ahí sería ruido.
struct BeaconInterruptedBlock<Renew: View>: View {
    let state: BeaconFlareState
    @ViewBuilder let renew: Renew

    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        if let copy = BeaconFlareCopy.interrupted(state) {
            VStack(alignment: .leading, spacing: 6) {
                Text(l10n.t(copy.title))
                    .font(.bpScaled(16, weight: .black))
                    .foregroundStyle(.white)
                Text(l10n.t(copy.body))
                    .font(.bpScaled(13))
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                if state == .expired { renew.padding(.top, 4) }
            }
            .padding(BPSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: BPRadius.md))
        }
    }
}

// MARK: - Quién contestó

/// La única razón para seguir con el brazo en alto, o para bajarlo.
///
/// CERO RESPUESTAS NO ES "NADIE LO VIO": sin push no hay acuse de entrega, así
/// que lo único afirmable es quién CONTESTÓ, y el renglón chico lo aclara en
/// vez de dejar que el silencio se lea como abandono.
struct BeaconAckRow: View {
    let beacon: SafetyBeacon

    @ObservedObject private var l10n = L10n.shared

    private var answered: String? {
        guard beacon.ackCount > 0 else { return nil }
        // Sin nombres —todos reservados o sin perfil— contamos, que es lo que
        // sabemos. Armar "En camino: y 2 más" sería una frase rota.
        guard !beacon.ackNames.isEmpty else {
            return String(format: l10n.t("beacon.broadcast.onTheirWayCount"), beacon.ackCount)
        }
        var parts = beacon.ackNames
        if beacon.unnamedAckCount > 0 {
            parts.append(String(format: l10n.t("safety.ack.andMore"), beacon.unnamedAckCount))
        }
        return String(format: l10n.t("beacon.broadcast.onTheirWay"), parts.joined(separator: ", "))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(answered ?? l10n.t("safety.ack.none"))
                .font(.bpScaled(14, weight: answered == nil ? .semibold : .black))
                .foregroundStyle(answered == nil ? .white.opacity(0.6) : Color.bpGreen)
                .fixedSize(horizontal: false, vertical: true)
            if answered == nil {
                Text(l10n.t("safety.ack.unknownDelivery"))
                    .font(.bpScaled(11))
                    .foregroundStyle(.white.opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Las dos cuentas regresivas

/// Vencen distinto y por eso se muestran las dos: la sesión de hardware
/// (10 min, renovable con un toque, la que apaga el brillo y la linterna) y el
/// beacon que tu gente ve. Refresco cada 15 s — `BeaconClock` cuenta por
/// minutos, medir más seguido no agrega nada y despierta la pantalla al pedo.
struct BeaconSessionFooter<Renew: View>: View {
    let beacon: SafetyBeacon
    @ViewBuilder let renew: Renew

    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var flares = BeaconFlares.shared

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 15)) { _ in
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: BPSpacing.sm) {
                    Text(String(format: l10n.t("beacon.timeRemaining"),
                                BeaconClock.remaining(BeaconFlareCopy.sessionRemaining(flares.state), l10n)))
                        .font(.bpScaled(13, weight: .bold))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    Spacer(minLength: BPSpacing.sm)
                    renew
                }
                Text(String(format: l10n.t("safety.beacon.expiresIn"),
                            BeaconClock.remaining(beacon.secondsRemaining, l10n)))
                    .font(.bpScaled(11))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }
}

struct BeaconRenewButton: View {
    let action: () -> Void

    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        Button(action: action) {
            Text(l10n.t("beacon.renew"))
                .font(.bpScaled(12, weight: .heavy))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color.bpAmber, in: Capsule())
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: l10n.t("beacon.renew"), isButton: true)
    }
}

// MARK: - Apagar, sin apagar de casualidad

/// Esta pantalla se va a rozar con la mano mientras está en alto, así que un
/// toque suelto no puede apagarla. Hace falta un segundo de presión continua,
/// con el relleno avanzando a la vista: un roce que empezó por accidente se ve
/// avanzar y se suelta a tiempo.
///
/// Con VoiceOver el gesto no existe —mantener el dedo quieto sobre un elemento
/// es otra cosa para VoiceOver— así que ahí es un botón común. Enfocar y hacer
/// doble toque ya es deliberado, y dejar el gesto sería cerrarle la salida a
/// quien menos puede mirar la pantalla. Mismo criterio que `HoldToRaiseButton`.
struct HoldToEndButton: View {
    static let holdDuration: Double = 1.0

    let title: String, caption: String, hint: String
    let isBusy: Bool
    let action: () -> Void

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var isPressing = false

    var body: some View {
        Group {
            if voiceOver {
                Button(action: action) { face }.buttonStyle(.plain)
            } else {
                face.onLongPressGesture(
                    minimumDuration: Self.holdDuration,
                    pressing: { pressing in
                        guard !isBusy else { return }
                        if pressing { BPHaptics.light() }
                        // El relleno DURA lo que dura el gesto: no es adorno,
                        // es cuánto falta. Por eso tampoco lo apaga "Reducir
                        // movimiento" — sin él el gesto queda opaco.
                        withAnimation(.linear(duration: pressing ? Self.holdDuration : 0.15)) {
                            isPressing = pressing
                        }
                    },
                    perform: { if !isBusy { action() } }
                )
            }
        }
        .disabled(isBusy)
        .opacity(isBusy ? 0.5 : 1)
        .bpAccessibility(label: title, hint: hint, isButton: true)
    }

    private var face: some View {
        VStack(spacing: 3) {
            Text(title).font(.bpScaled(17, weight: .black, design: .rounded))
            Text(caption)
                .font(.bpScaled(11, weight: .semibold))
                .opacity(0.75)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(Color.black)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(alignment: .leading) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Color.white.opacity(0.5)
                    Color.white.frame(width: isPressing ? proxy.size.width : 0)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: BPRadius.xl))
        .contentShape(RoundedRectangle(cornerRadius: BPRadius.xl))
    }
}
