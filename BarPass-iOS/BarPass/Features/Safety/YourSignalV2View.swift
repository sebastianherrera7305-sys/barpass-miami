import SwiftUI

// YourSignalV2View — "Tu señal" (grupo "Cuenta y seguridad") del artifact
// de pantallas v17.1, líneas 2819-2907 (sección #s-beacon). Esta pantalla
// NO sigue la paleta oscura general: es un faro visual — fondo DORADO a
// full con parpadeo lento, tres anillos expandiéndose desde el centro, y
// un avatar grande con la instrucción "Levántalo por encima de la cabeza".
// El propósito es que te encuentren en una multitud: el teléfono se vuelve
// una antorcha visible y la pantalla te dice quién viene en camino.
//
// Elementos del mockup:
// - Status bar oscuro (23:41 · SOS · 63%) sobre fondo dorado.
// - HUD superior (vidrio oscuro): "Tu señal · DORADO · parpadeo lento" + timer
//   circular de 9:40 restantes.
// - Core: ▲ latiendo, avatar grande amarillo, "Levántalo por encima de la cabeza".
// - Radar card (vidrio oscuro): "Vienen a buscarte · 2 / linterna encendida"
//   con dos filas (Mía 40m izquierda, Jules 120m desde la barra) + flechas.
// - Hold-to-slide "Desliza · me encontraron" + nota "Salir de esta pantalla ·
//   la señal sigue encendida".
//
// Limitaciones conocidas:
// - La data (contactos que vienen, tiempo restante, ángulos de las flechas)
//   es literal del mockup. No se conecta a FriendPresence / LocationService /
//   un canal de "beacon activo" todavía — ese wiring es un pase siguiente.
// - El slide-to-confirm es un gesto completo (drag + threshold) pero su
//   acción al confirmarse sólo apaga el beacon localmente y hace dismiss.
//   No notifica a los contactos ni corta el broadcast del backend.
// - La linterna real (AVCaptureDevice torchMode) no se activa aquí para no
//   requerir permisos ni cambios de Info.plist; la pantalla sola ya es
//   visible desde lejos. La fila "linterna encendida" del HUD describe la
//   intención del flujo, no un side-effect activo.
// - Los avatares son SF Symbols a color — no se replican los SVG estilizados
//   del mockup para no inflar el archivo. Los avatares reales deben venir
//   del usuario y sus contactos de confianza.

@MainActor
struct YourSignalV2View: View {
    @Environment(\.dismiss) private var dismiss

    // Mockup data — ver comentario de limitaciones.
    private let timeRemaining: TimeInterval = 9 * 60 + 40
    private let batteryLabel = "63%"
    private let clockLabel = "23:41"

    @State private var pulse: Double = 0
    @State private var arrowBounce: Double = 0
    @State private var ripplePhase: Double = 0
    @State private var slideOffset: CGFloat = 0
    @State private var confirmed = false

    var body: some View {
        ZStack {
            // Fondo dorado a full con parpadeo lento (radial gradient animado).
            YourSignalV2Background(pulse: pulse)

            // Tres anillos que se expanden desde el centro del avatar.
            YourSignalV2Rings(phase: ripplePhase)

            VStack(spacing: 0) {
                fakeStatusBar
                    .padding(.horizontal, 22)
                    .padding(.top, 14)

                Spacer(minLength: 10)

                topHUD
                    .padding(.horizontal, 18)
                    .padding(.top, 46)

                Spacer(minLength: 12)

                core
                    .padding(.horizontal, 20)

                Spacer(minLength: 12)

                radar
                    .padding(.horizontal, 18)
                    .padding(.bottom, 26)
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
        }
    }

    // MARK: - Fake status bar (dark text sobre dorado)

    private var fakeStatusBar: some View {
        HStack {
            Text(clockLabel)
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundStyle(Color.black.opacity(0.78))
            Spacer()
            HStack(spacing: 8) {
                Text("SOS")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(Color.black.opacity(0.9))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.black.opacity(0.35)))
                Text(batteryLabel)
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Color.black.opacity(0.78))
            }
        }
    }

    // MARK: - Top HUD (dark glass + timer)

    private var topHUD: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Tu señal")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(Color.white.opacity(0.65))
                Text("DORADO · parpadeo lento")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(Color.bpAmberBright)
            }

            Spacer(minLength: 10)

            timerBadge
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

    private var timerBadge: some View {
        ZStack {
            Circle()
                .stroke(Color.black.opacity(0.28), lineWidth: 4)
                .frame(width: 44, height: 44)
            Circle()
                .trim(from: 0, to: 0.96)
                .stroke(Color.bpAmberBright, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 44, height: 44)
                .rotationEffect(.degrees(-90))
            Text(formattedTime(timeRemaining))
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

            Text("Levántalo por encima de la cabeza")
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

    // MARK: - Radar card (quién viene en camino + slide)

    private var radar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Vienen a buscarte · 2")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(Color.white.opacity(0.78))
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "flashlight.on.fill")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Color.bpAmberBright)
                    Text("linterna encendida")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(Color.white.opacity(0.72))
                }
            }

            YourSignalRow(
                name: "Mía",
                distance: "40 m",
                detail: "a tu izquierda · llega en 1 min",
                tint: Color(red: 0.55, green: 0.4, blue: 0.95),
                arrowAngle: -70
            )

            YourSignalRow(
                name: "Jules",
                distance: "120 m",
                detail: "viene desde la barra",
                tint: Color.bpGreen,
                arrowAngle: 30
            )

            slidePill

            Text("Salir de esta pantalla · la señal sigue encendida")
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

    // MARK: - Slide to confirm "me encontraron"

    private var slidePill: some View {
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
                                guard !confirmed else { return }
                                slideOffset = min(max(0, v.translation.width), maxOffset)
                            }
                            .onEnded { _ in
                                guard !confirmed else { return }
                                if slideOffset > maxOffset * 0.75 {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        slideOffset = maxOffset
                                        confirmed = true
                                    }
                                    hapticSuccess()
                                    Task { @MainActor in
                                        try? await Task.sleep(nanoseconds: 650_000_000)
                                        dismiss()
                                    }
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
            Image(systemName: confirmed ? "checkmark" : "chevron.right")
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(.black)
        }
    }

    private func hapticSuccess() {
        #if canImport(UIKit)
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.success)
        #endif
    }
}

// MARK: - Row (contacto que viene en camino)

@MainActor
private struct YourSignalRow: View {
    let name: String
    let distance: String
    let detail: String
    let tint: Color
    let arrowAngle: Double

    var body: some View {
        HStack(spacing: 12) {
            // Avatar en bloque de color — approximation de los SVG del mockup.
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
                HStack(spacing: 6) {
                    Text(name)
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("· \(distance)")
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
                Text(detail)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Text("➤")
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(Color.bpAmberBright)
                .rotationEffect(.degrees(arrowAngle))
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

#Preview {
    YourSignalV2View()
}
