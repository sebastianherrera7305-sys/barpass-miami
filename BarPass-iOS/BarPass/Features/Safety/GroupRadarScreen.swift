import SwiftUI

/// La cubierta a pantalla completa: muestra el RADAR mientras dos personas se
/// buscan y, cuando el líder enciende el punto de encuentro, ESE PUNTO. Es UNA cubierta con
/// contenido cambiante (no varias que se presentan y descartan a la vez); la
/// presenta `SafetyCoverPresenter` según `router.isCoverPresented`.
///
/// El radar del faro de AUXILIO de siempre (`ProximityRadarView`) va en un `.sheet`
/// DENTRO de esta cubierta, ligado a `router.beaconRadar`: así su
/// `@Environment(\.dismiss)` cierra de verdad (pone el binding en nil) sin que
/// esa pantalla —que no se toca— tenga que saber nada de este router.
struct SafetyCoverHost: View {
    @ObservedObject private var router = SafetyPushRouter.shared

    var body: some View {
        content
            .sheet(item: Binding(
                get: { router.beaconRadar },
                set: { if $0 == nil { router.dismissBeaconRadar() } }
            )) { target in
                ProximityRadarView(beacon: target, peerUserId: target.userId, peerName: target.name)
            }
    }

    @ViewBuilder private var content: some View {
        if let rally = router.rallyPoint {
            RallyPointScreen(request: rally) { router.finishRallyPoint() }
        } else if let radar = router.radar {
            // La identidad es la búsqueda: un radar nuevo es un canal de
            // tokens nuevo (el viejo no se puede reabrir después de cerrarse).
            GroupRadarScreen(request: radar).id(radar.seekId)
        } else {
            // Sólo el radar del faro está abierto (arriba, en su sheet): el
            // fondo es el de la app, no un negro que parezca un error.
            BPBackgroundView().ignoresSafeArea()
        }
    }
}

/// ESTADOS A y C de la máquina: el radar direccional de UNA búsqueda, visto
/// desde el buscador o desde el líder.
///
/// Reutiliza tal cual `ProximityRadarDial` (la flecha, la distancia, los
/// estados honestos de Sebastián) y `ProximityRadar` (la NISession); lo único
/// nuevo acá es lo que se hace cuando se cruzan los 9 m (30 ft), y sólo en el
/// teléfono del líder:
///
///  · vibración fuerte y acotada (`HandshakeHapticPattern`)
///  · un banner LOCAL: "Juan está a menos de 30 ft. Tocá para encender el punto de encuentro."
///
/// Tocar ese banner es el ESTADO E. El buscador nunca ve ese botón: sólo
/// aprende que está cerca y que es el líder quien enciende el punto de encuentro.
///
/// Foreground siempre: NearbyInteraction no mide en segundo plano, y esta
/// pantalla no lo disimula — si la app sale de primer plano el radar queda
/// pausado (`ProximityRadarState.paused`) y vuelve al regresar.
struct GroupRadarScreen: View {
    let request: SafetyPushRouter.RadarRequest

    @StateObject private var manager: ProximityRadarManager
    @ObservedObject private var router = SafetyPushRouter.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var isLighting = false

    init(request: SafetyPushRouter.RadarRequest) {
        self.request = request
        let channel = SafetySeekTokenChannel(seekId: request.seekId)
        _manager = StateObject(wrappedValue: ProximityRadarManager(role: request.role, channel: channel))
    }

    private var state: ProximityRadarState { manager.radarState }

    var body: some View {
        ZStack(alignment: .top) {
            BPBackgroundView()

            VStack(spacing: BPSpacing.lg) {
                topBar
                header
                ProximityRadarDial(state: state)
                    .accessibilityElement(children: .ignore)
                    .bpAccessibility(label: spokenState)
                readout
                roleNote
                manualRallyPoint
                refusal
                Spacer(minLength: 0)
            }
            .padding(.horizontal, BPSpacing.lg)
            .padding(.top, BPSpacing.md)

            // El banner LOCAL del apretón de manos: sólo el líder.
            if manager.showsHandshakeBanner, request.role.canLightRallyPoint {
                handshakeBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: manager.showsHandshakeBanner)
        .onAppear { manager.start() }
        // OBLIGATORIO: el motor no tiene deinit. Sin esto quedan corriendo la
        // NISession, el tick de 250 ms y el poll de tokens al backend.
        .onDisappear { manager.stop() }
        .task(id: request.expiresAt) {
            let wait = request.expiresAt.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled else { return }
            router.finishRadar()
        }
    }

    // MARK: - Piezas

    private var topBar: some View {
        HStack {
            Button {
                router.finishRadar()
            } label: {
                Text(request.role == .seeker ? l10n.t("safetyGroup.seek.stop") : l10n.t("groupRadar.close"))
                    .font(.bpHeadline())
                    .foregroundStyle(Color.bpAmber)
            }
            .bpAccessibility(label: l10n.t("groupRadar.close"), isButton: true)
            Spacer()
        }
        .padding(.top, BPSpacing.sm)
    }

    private var header: some View {
        VStack(spacing: BPSpacing.xs) {
            Text(request.peerName)
                .font(.bpTitle1())
                .foregroundStyle(Color.bpInk)
            Text(l10n.t(state.messageKey))
                .font(.bpScaled(13))
                .foregroundStyle(Color.bpTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .bpEntrance(offset: CGSize(width: 0, height: 10))
    }

    /// La distancia, formateada para el idioma y la región (pies en EE. UU.,
    /// metros en el resto). `.arrived` no muestra número: a 1,5 m mirar el
    /// teléfono es peor que levantar la cabeza.
    @ViewBuilder private var readout: some View {
        if let meters = state.meters, !isArrived {
            Text(RadarDistanceFormat.text(meters: meters))
                .font(.system(size: 44, weight: .black, design: .rounded))
                .foregroundStyle(Color.bpInk)
                .monospacedDigit()
        }
    }

    private var isArrived: Bool {
        if case .arrived = state { return true }
        return false
    }

    /// Lo que cada rol necesita saber, sin prometer más de lo que hay.
    @ViewBuilder private var roleNote: some View {
        switch (request.role, manager.phase) {
        case (.seeker, .handshake):
            note(String(format: l10n.t("groupRadar.seeker.close"), request.peerName))
        case (.seeker, _):
            note(String(format: l10n.t("groupRadar.seeker.waiting"), request.peerName))
        case (.leader, .handshake):
            EmptyView() // el banner de arriba ya lo dice
        case (.leader, _):
            note(String(format: l10n.t("groupRadar.leader.connecting"), request.peerName))
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.bpScaled(13))
            .foregroundStyle(Color.bpTextSecondary)
            .multilineTextAlignment(.center)
            .padding(BPSpacing.md)
            .frame(maxWidth: .infinity)
            .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.md))
    }

    /// Un teléfono sin UWB nunca cruza los 9 m. Sigue siendo del líder, sigue
    /// siendo un toque en primer plano y sigue pasando por el servidor.
    @ViewBuilder private var manualRallyPoint: some View {
        if manager.needsManualRallyPoint {
            Button {
                light()
            } label: {
                Text(l10n.t("groupRadar.rally.manual"))
                    .font(.bpHeadline())
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.bpAmber, in: RoundedRectangle(cornerRadius: BPRadius.lg))
            }
            .disabled(isLighting)
        }
    }

    @ViewBuilder private var refusal: some View {
        if let error = router.rallyRefusal {
            Text(error.errorDescription ?? "")
                .font(.bpScaled(12))
                .foregroundStyle(Color.bpDanger)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - El banner de los 30 ft (ESTADO D → E)

    private var handshakeBanner: some View {
        Button {
            light()
        } label: {
            HStack(spacing: BPSpacing.md) {
                Image(systemName: "flashlight.on.fill")
                    .font(.system(size: 22, weight: .bold))
                Text(String(format: l10n.t("groupRadar.handshake.banner"), request.peerName))
                    .font(.bpHeadline())
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.black)
            .padding(BPSpacing.md)
            .frame(maxWidth: .infinity)
            .background(Color.bpAmber, in: RoundedRectangle(cornerRadius: BPRadius.lg))
            .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
        }
        .disabled(isLighting)
        .padding(.horizontal, BPSpacing.md)
        .padding(.top, BPSpacing.sm)
        .accessibilityAddTraits(.isButton)
    }

    /// El líder tocó: se corta la vibración PRIMERO (ya cumplió) y se pide el
    /// punto de encuentro. Si el servidor lo rechaza, el radar sigue ahí y `refusal` dice por
    /// qué; si sale bien, el router cambia el contenido de la cubierta.
    private func light() {
        guard !isLighting else { return }
        isLighting = true
        manager.dismissBanner()
        Task {
            await router.lightRallyPoint()
            isLighting = false
        }
    }

    // MARK: - Accesibilidad

    private var spokenState: String {
        var parts = [l10n.t(state.messageKey)]
        if let meters = state.meters, !isArrived { parts.append(RadarDistanceFormat.text(meters: meters)) }
        if state.heading?.isConfirmed == false { parts.append(l10n.t("radar.directed.unconfirmed")) }
        return parts.joined(separator: ". ")
    }
}

/// Formato de la distancia, aparte para que ninguna pantalla invente el suyo.
/// Usa el sistema de medidas de la región del teléfono (pies en EE. UU.).
enum RadarDistanceFormat {
    static func text(meters: Double) -> String {
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .naturalScale
        formatter.unitStyle = .short
        formatter.numberFormatter.maximumFractionDigits = meters < 10 ? 1 : 0
        return formatter.string(from: Measurement(value: max(0, meters), unit: UnitLength.meters))
    }
}
