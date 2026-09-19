import SwiftUI
import UIKit

/// La sesión viva del radar: es dueña del motor y traduce UN estado en lo que
/// se ve, se lee y se puede tocar.
///
/// Está separada de `ProximityRadarView` porque su IDENTIDAD ES LA SESIÓN.
/// `SafetyBeaconTokenChannel` no se puede reabrir después de `close()`, así que
/// un botón de reintentar que llamara `stop()` + `start()` dejaría un canal
/// muerto y la pantalla esperando para siempre — justo la pantalla girando que
/// no queremos. Recrear esta vista (`.id(attempt)` desde arriba) es lo que da
/// un canal nuevo de verdad.
struct ProximityRadarSession: View {
    let beacon: SafetyBeacon
    let peerUserId: String
    let onRetry: () -> Void

    @StateObject private var radar: ProximityRadar
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.openURL) private var openURL

    /// Cuándo entró el estado actual. Sirve para una sola cosa: ninguna
    /// pantalla de esta app se queda girando para siempre — si esperar es lo
    /// único que pasa hace 15 s, el color se ofrece con todas las letras.
    @State private var stateSince = Date()

    init(beacon: SafetyBeacon, peerUserId: String, onRetry: @escaping () -> Void) {
        self.beacon = beacon
        self.peerUserId = peerUserId
        self.onRetry = onRetry
        let channel = SafetyBeaconTokenChannel(beaconId: beacon.id, peerUserId: peerUserId)
        _radar = StateObject(wrappedValue: ProximityRadar(channel: channel))
    }

    private var state: ProximityRadarState { radar.state }
    /// Derivado del id del beacon, que es lo único que los dos lados tienen
    /// garantizado en común. Se pide al store para que exista un solo lugar que
    /// decida color y ritmo.
    private var signal: BeaconSignal { SafetyBeaconStore.shared.signal(for: beacon) }

    var body: some View {
        VStack(spacing: BPSpacing.lg) {
            if state.shouldFallBackToBeacon {
                // El color de protagonista: es el camino que funciona en TODOS
                // los teléfonos, y en estos estados es el único que hay.
                ProximityRadarFallbackCard(beacon: beacon, signal: signal)
                message
            } else {
                VStack(spacing: BPSpacing.md) {
                    ProximityRadarDial(state: state)
                    readout
                }
                .accessibilityElement(children: .ignore)
                .bpAccessibility(label: spokenState)
                message
            }
            actions
        }
        .bpEntrance(offset: CGSize(width: 0, height: 14), delay: 0.05)
        .onAppear { radar.start() }
        // OBLIGATORIO: el motor no tiene deinit. Sin esto quedan corriendo la
        // NISession, el tick de 250 ms y —lo que de verdad escala mal— un poll
        // al backend cada 3 s por cada pantalla que alguien abrió y dejó atrás.
        .onDisappear { radar.stop() }
        .onChange(of: state) { old, new in
            stateSince = Date()
            // En un salón lleno nadie está mirando la pantalla justo cuando
            // llega. `old` ya en fallback = seguimos en `.arrived`, no es una
            // llegada nueva.
            if case .arrived = new, !old.shouldFallBackToBeacon { BPHaptics.success() }
        }
    }

    // MARK: - El número

    /// Hay un caso donde ningún número es honesto: `.arrived`. A 1,5 m la
    /// flecha ya es ruido y la persona está a la vista; seguir mostrando
    /// "1,4 m" invita a mirar el teléfono en vez de levantar la cabeza. Por eso
    /// `.arrived` cae del lado del color y no pasa por acá.
    @ViewBuilder private var readout: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if let meters = state.meters {
                Text(RadarText.number(meters, language: l10n.language))
                    .font(.bpScaled(52, weight: .black, design: .rounded))
                    .foregroundStyle(Color.bpInk)
                    .contentTransition(.numericText())
                Text(RadarText.unit)
                    .font(.bpScaled(20, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.bpTextSecondary)
            } else if case .signalLost(let last, let at) = state {
                lastKnown(last, at: at)
            } else {
                // Sin distancia no hay número. El guion ocupa el lugar para que
                // la tipografía no salte cuando llegue la primera medición.
                Text("—")
                    .font(.bpScaled(52, weight: .black, design: .rounded))
                    .foregroundStyle(Color.bpTextTertiary)
            }
        }
    }

    /// El último número NUNCA con la tipografía del número vivo: chico,
    /// terciario y fechado abajo. Un número quieto que parece actual es el
    /// mismo error que una flecha congelada.
    private func lastKnown(_ meters: Double?, at: Date) -> some View {
        VStack(spacing: 2) {
            if let meters {
                Text(RadarText.distance(meters, language: l10n.language))
                    .font(.bpTitle2())
                    .foregroundStyle(Color.bpTextTertiary)
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(RadarText.fill(l10n.t("radar.signalLost.age"),
                                    RadarText.age(context.date.timeIntervalSince(at))))
                    .font(.bpCaption())
                    .foregroundStyle(Color.bpTextSecondary)
            }
        }
    }

    // MARK: - Las palabras

    private var message: some View {
        VStack(spacing: BPSpacing.sm) {
            Text(headline)
                .font(.bpHeadline())
                .foregroundStyle(Color.bpInk)
                .multilineTextAlignment(.center)
            if let caveat = staleArrowCaveat {
                Text(caveat)
                    .font(.bpCaption())
                    .foregroundStyle(Color.bpTextSecondary)
                    .multilineTextAlignment(.center)
            }
            if showsPostureHint {
                // El azimut es un ángulo en el plano de la PANTALLA: se lee
                // como un mapa con el teléfono horizontal. Se enseña antes de
                // que haga falta, no recién cuando la geometría se degenera.
                Text(l10n.t("radar.posture.hint"))
                    .font(.bpSmall())
                    .foregroundStyle(Color.bpTextTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var headline: String {
        // `.directed` puede traer rumbo sin distancia: sabemos para dónde, no a
        // cuánto. La frase con `{0}` no sirve vacía.
        if case .directed(let meters, _) = state, meters == nil {
            return l10n.t("radar.directed.noDistance")
        }
        let distance = state.meters.map { RadarText.distance($0, language: l10n.language) } ?? ""
        return RadarText.fill(l10n.t(state.messageKey), distance)
    }

    /// `radar.directed.unconfirmed` ya trae el aviso cuando hay distancia;
    /// cuando no la hay, el aviso va igual, aparte.
    private var staleArrowCaveat: String? {
        guard case .directed(let meters, let heading) = state,
              !heading.isConfirmed, meters == nil else { return nil }
        return l10n.t("radar.directed.stale")
    }

    private var showsPostureHint: Bool {
        switch state {
        // En `.directed` la flecha ya funciona y la lección sobra; en
        // `.holdPhoneFlat` el mensaje del motor lo dice más fuerte.
        case .acquiring, .waitingForPeer, .distanceOnly: return true
        default: return false
        }
    }

    /// Lo que oye VoiceOver. La flecha atenuada no existe para quien no ve la
    /// pantalla, así que el aviso de vector viejo viaja acá también: si esto se
    /// pierde, la regla de honestidad vale sólo para los que miran.
    private var spokenState: String {
        guard case .directed(let meters, let heading) = state else { return headline }
        let hour = "\(RadarText.clockHour(heading.azimuth))"
        var spoken: String
        if let meters {
            spoken = RadarText.fill(l10n.t("radar.accessibility.arrow"),
                                    RadarText.distance(meters, language: l10n.language), hour)
        } else {
            spoken = RadarText.fill(l10n.t("radar.accessibility.direction"), hour)
        }
        if !heading.isConfirmed { spoken += " " + l10n.t("radar.directed.stale") }
        return spoken
    }

    // MARK: - Qué puede hacer

    @ViewBuilder private var actions: some View {
        VStack(spacing: BPSpacing.md) {
            if state == .permissionDenied {
                button(l10n.t("radar.permissionDenied.action")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
            // Los dos estados cuya copia promete un reintento.
            if case .failed = state { button(l10n.t("radar.retry"), action: onRetry) }
            if state == .peerLeft { button(l10n.t("radar.retry"), action: onRetry) }

            if !state.shouldFallBackToBeacon {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    // Esperar es un estado legítimo; esperar sin salida no lo
                    // es. A los 15 s el color se ofrece explícitamente.
                    if isStalledWaiting(now: context.date) {
                        Text(l10n.t("radar.fallback.meanwhile"))
                            .font(.bpCaption())
                            .foregroundStyle(Color.bpAmber)
                            .frame(maxWidth: .infinity)
                    }
                }
                // Siempre presente, aunque el radar ande: nadie tendría que
                // descubrir que el color existía recién cuando el radar falla.
                ProximityRadarFallbackCard(beacon: beacon, signal: signal, isCompact: true)
            }
        }
    }

    private func isStalledWaiting(now: Date) -> Bool {
        switch state {
        case .waitingForPeer, .acquiring, .signalLost:
            return now.timeIntervalSince(stateSince) >= 15
        default:
            return false
        }
    }

    private func button(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            BPHaptics.light()
            action()
        } label: {
            Text(title)
                .font(.bpHeadline())
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, BPSpacing.md)
                .background(Color.bpAmber, in: RoundedRectangle(cornerRadius: BPRadius.md))
        }
        .bpAccessibility(label: title, isButton: true)
    }
}
