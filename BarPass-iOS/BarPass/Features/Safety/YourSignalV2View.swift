import SwiftUI

// YourSignalV2View — "Tu señal" (grupo "Cuenta y seguridad") del artifact
// de pantallas v17.1, líneas 2819-2907 (sección #s-beacon). Esta pantalla
// NO sigue la paleta oscura general: es un faro visual — fondo DORADO a
// full con parpadeo lento, tres anillos expandiéndose desde el centro, y
// un avatar grande con la instrucción "Levántalo por encima de la cabeza".
// El propósito es que te encuentren en una multitud: el teléfono se vuelve
// una antorcha visible y la pantalla te dice quién viene en camino.
//
// 2026-10-10 — datos reales conectados contra el stack de seguridad V1:
//
//  · `SafetyBeaconStore.shared.mine` manda. Color, ritmo, tiempo que falta,
//    cantidad de respuestas y nombres de quien contestó salen de ese
//    SafetyBeacon — nunca inventados. Si NO hay beacon mío encendido, la
//    pantalla se muestra como un empty state con botón de dismiss (no se
//    renderiza el faro — es exactamente lo que la vista promete y no hay).
//  · "DORADO · parpadeo lento" se compone de los l10n keys reales de
//    BeaconSignal (`colorNameKey` / `rhythmNameKey`), así que un dicrómata
//    o alguien con pantalla saturada por el bar lee el nombre escrito y no
//    sólo el color.
//  · "Vienen a buscarte · N" muestra `beacon.ackCount`. Cuando es 0 decimos
//    "nadie contestó todavía" en vez de poner "0" (ver BeaconAckRow V1).
//  · Las filas listan quienes CONTESTARON (`beacon.ackNames`) con el avatar
//    tintado al color del propio beacon. NO hay distancias ni flechas de
//    dirección: eso lo da NearbyInteraction en ProximityRadar, y es sesión
//    1 a 1, no se puede fabricar para un grupo entero.
//  · "Linterna encendida" en el HUD del radar sólo aparece cuando
//    `BeaconFlares.shared.state` reporta la torch como `.pulsing`. Si está
//    atenuada o apagada por batería/calor, el badge cambia (misma data que
//    BeaconFlareStatusList de V1).
//  · El slide-to-confirm "me encontraron" llama al repo real
//    (`RepositoryDependencies.safetyBeacon.resolve(beaconId:)`) + dismiss.
//    Es lo único que apaga la baliza: mientras la fila siga viva el store
//    la vuelve a encender en el próximo tick (mismo contrato que
//    BeaconBroadcastView).
//
// Limitaciones conocidas:
//  · Los avatares son SF Symbols a color — no se replican los SVG
//    estilizados del mockup. Siguen la paleta real de BeaconIdentity.
//  · La linterna real (AVCaptureDevice torchMode) la enciende el servicio
//    `BeaconFlares` cuando el beacon se levanta; esta pantalla sólo
//    REFLEJA ese estado, no lo prende por su cuenta.
//  · Como el beacon tiene su propia fuente de verdad del tiempo que falta,
//    el badge del timer se refresca cada 5 s con un TimelineView en vez de
//    con un `Timer.publish` separado — misma técnica que BeaconSessionFooter.

@MainActor
struct YourSignalV2View: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    // Override para previews — si viene, se usa en vez del store real.
    var beaconOverride: SafetyBeacon? = nil
    var flareStateOverride: BeaconFlareState? = nil

    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var beaconStore = SafetyBeaconStore.shared
    @ObservedObject private var flares = BeaconFlares.shared

    @State private var pulse: Double = 0
    @State private var arrowBounce: Double = 0
    @State private var ripplePhase: Double = 0
    @State private var slideOffset: CGFloat = 0
    @State private var confirmed = false
    @State private var isResolving = false
    @State private var resolveError: String?

    // MARK: - Datos reales derivados

    /// Si viene un override (preview), lo usa; si no, el beacon mío vivo.
    private var mine: SafetyBeacon? {
        if let beaconOverride { return beaconOverride }
        return beaconStore.mine.flatMap { $0.isResolved ? nil : $0 }
    }

    private var flareState: BeaconFlareState {
        flareStateOverride ?? flares.state
    }

    /// "DORADO" / "CELESTE" / "VERDE" / "FUCSIA" vía l10n real.
    private var colorName: String {
        guard let mine else { return "" }
        return l10n.t(mine.signal.colorNameKey)
    }

    /// "parpadeo lento" / "doble parpadeo" / etc.
    private var rhythmName: String {
        guard let mine else { return "" }
        return l10n.t(mine.signal.rhythmNameKey)
    }

    /// true cuando la linterna está pulsando y aportando luz real.
    private var torchIsOn: Bool {
        if case .active(let torch, _, _, _) = flareState {
            if case .pulsing = torch { return true }
        }
        return false
    }

    var body: some View {
        ZStack {
            // Fondo dorado a full con parpadeo lento.
            YourSignalV2Background(pulse: pulse)

            // Tres anillos que se expanden desde el centro del avatar.
            YourSignalV2Rings(phase: ripplePhase)

            if let mine {
                content(for: mine)
            } else {
                emptyState
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                pulse = 1
            }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                arrowBounce = 1
            }
            withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
                ripplePhase = 1
            }
            beaconStore.start()
        }
        // El poll sigue el ciclo de la app, igual que FindMyGroupView /
        // SafetyGroupView en V1: en background no hay a quién mostrarle nada
        // y cada consulta extra pega contra la red saturada del lugar.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { beaconStore.start() } else { beaconStore.stop() }
        }
    }

    @ViewBuilder
    private func content(for beacon: SafetyBeacon) -> some View {
        VStack(spacing: 0) {
            // Antes acá iba una barra de estado falsa (reloj + "SOS" + batería)
            // copiada del mockup. En el dispositivo esa fila era un segundo
            // reloj congelado, así que se quitó; el alto se conserva para que
            // el HUD no suba.
            Spacer().frame(height: 34)

            Spacer(minLength: 10)

            topHUD(for: beacon)
                .padding(.horizontal, 18)
                .padding(.top, 46)

            Spacer(minLength: 12)

            core
                .padding(.horizontal, 20)

            Spacer(minLength: 12)

            radar(for: beacon)
                .padding(.horizontal, 18)
                .padding(.bottom, 26)
        }
    }

    /// Lo que mostramos cuando el store NO tiene beacon mío vivo. No es un
    /// error — es que esta pantalla sólo existe mientras haya una señal; si
    /// no la hay, se dice así y hay salida.
    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "flashlight.off.fill")
                .font(.system(size: 48, weight: .black))
                .foregroundStyle(Color.black.opacity(0.65))
            Text("No tienes una señal activa")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.85))
                .multilineTextAlignment(.center)
            Text(l10n.t("yoursignal.needRaise"))
                .font(.system(size: 13))
                .foregroundStyle(Color.black.opacity(0.65))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
            Spacer()
            Button {
                BPHaptics.light()
                dismiss()
            } label: {
                Text(l10n.t("common.close"))
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(Color.white.opacity(0.4), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.black.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 36)
        }
    }

    // MARK: - Top HUD (dark glass + timer)

    private func topHUD(for beacon: SafetyBeacon) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Tu señal")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(Color.white.opacity(0.65))
                Text("\(colorName) · \(rhythmName)")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(Color.bpAmberBright)
            }

            Spacer(minLength: 10)

            // Refresca cada 15 s — misma cadencia que BeaconSessionFooter V1,
            // porque el display está en minutos y medir más seguido no agrega
            // dato y despierta la pantalla al pedo.
            TimelineView(.periodic(from: Date(), by: 15)) { _ in
                timerBadge(for: beacon)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
    }

    private func timerBadge(for beacon: SafetyBeacon) -> some View {
        let total = max(0, beacon.secondsRemaining)
        let totalWindow = max(1, beacon.expiresAt.timeIntervalSince(beacon.createdAt))
        let progress = min(1.0, max(0.02, total / totalWindow))
        return ZStack {
            Circle()
                .stroke(Color.black.opacity(0.28), lineWidth: 4)
                .frame(width: 44, height: 44)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.bpAmberBright, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 44, height: 44)
                .rotationEffect(.degrees(-90))
            Text(formattedTime(total))
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white)
        }
    }

    private func formattedTime(_ t: TimeInterval) -> String {
        let total = max(0, Int(t))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Core (arrow + big avatar + say)

    private var core: some View {
        VStack(spacing: 14) {
            Text("▲")
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.78))
                .offset(y: -6 * arrowBounce)

            bigAvatar
                .frame(width: 112, height: 112)

            Text(l10n.t("yoursignal.raiseAbove"))
                .font(.system(size: 22, weight: .black, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.black.opacity(0.88))
                .frame(maxWidth: 240)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var bigAvatar: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.17, green: 0.11, blue: 0.03),
                            Color(red: 0.07, green: 0.04, blue: 0.09)
                        ],
                        center: UnitPoint(x: 0.5, y: 0.3),
                        startRadius: 2, endRadius: 70
                    )
                )

            // Hair cap
            Path { p in
                p.addEllipse(in: CGRect(x: 16, y: 12, width: 80, height: 70))
            }
            .fill(Color(red: 0.09, green: 0.07, blue: 0.06))
            .frame(width: 112, height: 112)

            // Face
            Circle()
                .fill(Color(red: 0.80, green: 0.58, blue: 0.42))
                .frame(width: 70, height: 76)
                .offset(y: 6)

            // Eyes
            HStack(spacing: 14) {
                Circle().fill(Color(red: 0.17, green: 0.11, blue: 0.07)).frame(width: 7, height: 7)
                Circle().fill(Color(red: 0.17, green: 0.11, blue: 0.07)).frame(width: 7, height: 7)
            }
            .offset(y: 2)

            // Smile
            Path { p in
                p.move(to: CGPoint(x: 0, y: 0))
                p.addQuadCurve(to: CGPoint(x: 20, y: 0),
                               control: CGPoint(x: 10, y: 10))
            }
            .stroke(Color(red: 0.25, green: 0.12, blue: 0.08), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: 20, height: 10)
            .offset(y: 18)

            // Amber body (shoulders peeking at bottom)
            Path { p in
                p.move(to: CGPoint(x: 0, y: 40))
                p.addQuadCurve(to: CGPoint(x: 112, y: 40),
                               control: CGPoint(x: 56, y: 10))
                p.addLine(to: CGPoint(x: 112, y: 56))
                p.addLine(to: CGPoint(x: 0, y: 56))
                p.closeSubpath()
            }
            .fill(Color.bpAmber)
            .frame(width: 112, height: 56)
            .offset(y: 42)
            .clipShape(Circle().inset(by: 2))
        }
        .frame(width: 112, height: 112)
        .overlay(
            Circle()
                .strokeBorder(Color(red: 0.10, green: 0.07, blue: 0.0), lineWidth: 3)
        )
        .shadow(color: Color(red: 0.47, green: 0.27, blue: 0, opacity: 0.55),
                radius: 20, x: 0, y: 14)
    }

    // MARK: - Radar card (quién contestó + slide)

    private func radar(for beacon: SafetyBeacon) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(ackHeaderText(for: beacon))
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(Color.white.opacity(0.78))
                Spacer()
                if torchIsOn {
                    HStack(spacing: 5) {
                        Image(systemName: "flashlight.on.fill")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(Color.bpAmberBright)
                        Text(l10n.t("yoursignal.flashlightOn"))
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .tracking(1.4)
                            .foregroundStyle(Color.white.opacity(0.72))
                    }
                }
            }

            if beacon.ackCount == 0 {
                noAckYet
            } else {
                ackList(for: beacon)
            }

            slidePill(for: beacon)

            if let resolveError {
                Text(resolveError)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.bpDanger)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(l10n.t("yoursignal.exitHint"))
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(Color.white.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color.black.opacity(0.62))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
    }

    private func ackHeaderText(for beacon: SafetyBeacon) -> String {
        beacon.ackCount == 0
            ? "Nadie contestó todavía"
            : "Vienen a buscarte · \(beacon.ackCount)"
    }

    private var noAckYet: some View {
        Text(l10n.t("yoursignal.noAck"))
            .font(.system(size: 11, design: .serif).italic())
            .foregroundStyle(Color.white.opacity(0.6))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 2)
    }

    @ViewBuilder
    private func ackList(for beacon: SafetyBeacon) -> some View {
        let maxShown = 4
        let signal = beacon.signal
        let tint = signal.color.color
        let shownNames = Array(beacon.ackNames.prefix(maxShown))
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(shownNames.enumerated()), id: \.offset) { _, name in
                YourSignalAckRow(name: name, tint: tint)
            }
            let shownCount = shownNames.count
            let hidden = beacon.ackCount - shownCount
            if hidden > 0 {
                Text("+ \(hidden) más contestaron")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(Color.white.opacity(0.6))
            }
        }
    }

    // MARK: - Slide to confirm "me encontraron"

    private func slidePill(for beacon: SafetyBeacon) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let maxOffset = w - 50
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.10))
                Capsule()
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)

                Text(confirmed ? "Señal apagada" : "Desliza · me encontraron")
                    .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .frame(maxWidth: .infinity)

                knob
                    .offset(x: 4 + slideOffset)
                    .gesture(
                        DragGesture()
                            .onChanged { v in
                                guard !confirmed, !isResolving else { return }
                                slideOffset = min(max(0, v.translation.width), maxOffset)
                            }
                            .onEnded { _ in
                                guard !confirmed, !isResolving else { return }
                                if slideOffset > maxOffset * 0.75 {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        slideOffset = maxOffset
                                    }
                                    resolveSignal(for: beacon)
                                } else {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        slideOffset = 0
                                    }
                                }
                            }
                    )
            }
        }
        .frame(height: 50)
    }

    private var knob: some View {
        ZStack {
            Circle()
                .fill(Color.bpAmberBright)
                .frame(width: 42, height: 42)
            Group {
                if isResolving {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.black)
                } else {
                    Image(systemName: confirmed ? "checkmark" : "chevron.right")
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(.black)
                }
            }
        }
    }

    /// Resuelve el beacon contra el repo real. El store apaga la baliza en
    /// cuanto `beacon.isResolved` es `true`, igual que BeaconBroadcastView.
    private func resolveSignal(for beacon: SafetyBeacon) {
        guard !isResolving, !confirmed else { return }
        isResolving = true
        resolveError = nil
        BPHaptics.success()
        Task {
            do {
                try await RepositoryDependencies.safetyBeacon.resolve(beaconId: beacon.id)
                beaconStore.refreshNow()
                confirmed = true
                try? await Task.sleep(nanoseconds: 650_000_000)
                dismiss()
            } catch {
                resolveError = (error as? SafetyBeaconError)?.errorDescription
                    ?? l10n.t("safety.error.generic")
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    slideOffset = 0
                }
                BPHaptics.error()
            }
            isResolving = false
        }
    }
}

// MARK: - Row (una respuesta al faro)

@MainActor
private struct YourSignalAckRow: View {
    let name: String
    let tint: Color
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        HStack(spacing: 12) {
            // Avatar en bloque de color — el del color del propio faro.
            ZStack {
                Circle()
                    .fill(tint)
                    .frame(width: 36, height: 36)
                Image(systemName: "person.fill")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Color.black.opacity(0.6))
            }
            .overlay(
                Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 1.5)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text(l10n.t("yoursignal.coming"))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Image(systemName: "figure.walk.motion")
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(Color.bpAmberBright)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Background (gold full + slow pulse + grain)

@MainActor
private struct YourSignalV2Background: View {
    let pulse: Double

    var body: some View {
        ZStack {
            // Capa base amber (no desaparece durante el blink).
            Color.bpAmber.ignoresSafeArea()

            // Radial gradient brillante que respira — el "parpadeo lento".
            RadialGradient(
                colors: [
                    Color(red: 1.0, green: 0.96, blue: 0.78),
                    Color(red: 0.96, green: 0.85, blue: 0.48),
                    Color.bpAmber,
                    Color(red: 0.79, green: 0.56, blue: 0.17)
                ],
                center: UnitPoint(x: 0.5, y: 0.46),
                startRadius: 20,
                endRadius: 420
            )
            .ignoresSafeArea()
            .opacity(0.55 + 0.45 * pulse)

            // Grano fino para que no lea como un gradient plano.
            GrainTexture(opacity: 0.10)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .blendMode(.multiply)
        }
    }
}

// MARK: - Rings (3 anillos expandiéndose)

@MainActor
private struct YourSignalV2Rings: View {
    let phase: Double

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width * 0.5, y: geo.size.height * 0.46)
            ZStack {
                ring(phase: phase, delay: 0.0, center: center)
                ring(phase: phase, delay: 0.33, center: center)
                ring(phase: phase, delay: 0.66, center: center)
            }
        }
        .allowsHitTesting(false)
    }

    private func ring(phase: Double, delay: Double, center: CGPoint) -> some View {
        let p = (phase + (1 - delay)).truncatingRemainder(dividingBy: 1)
        let size = 120 + p * 420
        let opacity = (1 - p) * 0.65
        return Circle()
            .strokeBorder(Color.white.opacity(opacity), lineWidth: 2)
            .frame(width: size, height: size)
            .position(center)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Your Signal — sin beacon activo") {
    YourSignalV2View()
}

#Preview("Your Signal — con respuestas (mock)") {
    YourSignalV2View(
        beaconOverride: SafetyBeacon(
            id: "preview-1",
            userId: "me",
            displayName: "Yo",
            avatarUrl: nil,
            venueId: nil,
            venueName: nil,
            note: "cerca de la barra",
            createdAt: Date().addingTimeInterval(-120),
            expiresAt: Date().addingTimeInterval(9 * 60 + 40),
            resolvedAt: nil,
            isMine: true,
            iAcked: false,
            ackCount: 2,
            ackNames: ["Mía", "Jules"],
            signalIndex: 0,
            signalVariant: 0
        )
    )
}
#endif
