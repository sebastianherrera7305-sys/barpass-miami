import SwiftUI

// GroupNightView — "La noche del grupo" (artifact 294356f9, pantalla 9).
//
// Objeto vivo que se usa durante un trip en curso: mapa con tu gente y ETA,
// hype del grupo, cuenta compartida, poll de la próxima parada, chat corto
// con reactions, momentos (fotos) y SOS. Es la pantalla 9 del mockup
// (líneas 737-894), traducida al mismo lenguaje visual que OnboardingV2Flow:
// fondo con el ojo de Miami ("CityArtMiami") + vignette cálido + grain,
// tipografías de sistema aproximando los displays del zine, cards sobre
// Color.white.opacity(0.04) con stroke 0.08.
//
// Estado: todas las secciones usan DATOS LITERALES del mockup (owner las
// convergió, así que no inventamos nada). No está cableada al Trip real —
// la pantalla se puede presentar como sheet/push y mostrar el estado-ideal
// de un trip en Wynwood. Wire-up al TripRepository + mapa real (MapLibre o
// MapKit) + chat/poll server-side + Stripe split pay se hace en pases
// siguientes. Lo listado en `limitations` indica qué sigue stub.

@MainActor
struct GroupNightView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    // Poll state is local so el usuario puede ver que su voto cambia la UI
    // aunque no persistamos nada todavía. Los conteos del mockup (3 vs 2)
    // ya cuentan el voto del user por "La Otra".
    @State private var pollChoice: Int = 0

    var body: some View {
        ZStack {
            GroupNightBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    GroupNightHeader(onBack: { dismiss() })
                        .padding(.top, 20)

                    GroupNightLiveRow()
                    GroupNightMapCard()

                    HStack(spacing: 10) {
                        GroupNightHypeCard()
                        GroupNightTabCard()
                    }

                    GroupNightPollCard(choice: $pollChoice)
                    GroupNightChatCard()
                    GroupNightMomentsCard()
                    GroupNightSOSButton()
                        .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 48)
            }
            .scrollIndicators(.hidden)

            // Overlay SOS pin arriba a la derecha, mismo patrón que OnboardingV2
            VStack {
                HStack {
                    Spacer()
                    Text("SOS")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .tracking(1.6)
                        .foregroundStyle(Color.bpAmber)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.bpAmber.opacity(0.3)))
                }
                .padding(.top, 18).padding(.horizontal, 28)
                Spacer()
            }
            .allowsHitTesting(false)
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Background (reusa el idioma de OnboardingV2Background: ojo Miami + grain + fade)

@MainActor
private struct GroupNightBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.015, blue: 0.04).ignoresSafeArea()

            GeometryReader { proxy in
                Image("CityArtMiami")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width * 2.4, height: proxy.size.width * 2.4)
                    .position(x: proxy.size.width * 0.5, y: proxy.size.height * -0.15)
                    .opacity(0.42)
            }
            .ignoresSafeArea()

            RadialGradient(
                colors: [.clear, Color(red: 0.27, green: 0.09, blue: 0).opacity(0.36)],
                center: UnitPoint(x: 0.5, y: 0.3),
                startRadius: 180, endRadius: 720
            )
            .ignoresSafeArea()
            .blendMode(.multiply)

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.9), Color.black],
                startPoint: UnitPoint(x: 0.5, y: 0.25),
                endPoint: .bottom
            )
            .ignoresSafeArea()

            GrainTexture(opacity: 0.12)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Header (eyebrow + headline mix + back + SOS warning chip)

@MainActor
private struct GroupNightHeader: View {
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Status strip (reloj + batería) — pequeño detalle del mockup
            HStack {
                Text("23:41")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(Color.white.opacity(0.55))
                Spacer()
                Text("63%")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(Color.white.opacity(0.45))
            }

            HStack(alignment: .center, spacing: 10) {
                Button {
                    onBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.08), in: Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.14)))
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Noche en Wynwood")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(Color.white.opacity(0.7))

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .heavy))
                    Text("SOS")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .tracking(1.4)
                }
                .foregroundStyle(Color.bpDanger)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(Color.bpDanger.opacity(0.14), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.bpDanger.opacity(0.35)))
            }

            // Caption-style eyebrow + display headline, idioma OnboardingV2
            VStack(alignment: .leading, spacing: 4) {
                Text("2 · La noche en vivo")
                    .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                    .tracking(2.6)
                    .foregroundStyle(Color.bpAmber)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Noche en")
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .tracking(-1)
                        .foregroundStyle(.white)
                    Text("Wynwood")
                        .font(.system(size: 34, design: .serif).italic())
                        .foregroundStyle(Color.bpAmberBright)
                }
            }
            .padding(.top, 2)
        }
    }
}

// MARK: - Live status row (en curso · 4 de 5 juntos)

@MainActor
private struct GroupNightLiveRow: View {
    var body: some View {
        HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.bpGreen)
                    .frame(width: 6, height: 6)
                    .overlay(Circle().stroke(Color.bpGreen.opacity(0.4), lineWidth: 4).scaleEffect(1.6).opacity(0.4))
                Text("En curso · parada 2 de 3")
                    .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                    .tracking(2.0)
                    .foregroundStyle(Color.bpGreen)
            }
            Spacer()
            Text("4 de 5 juntos")
                .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(Color.white.opacity(0.6))
        }
    }
}

// MARK: - Map card

/// Representación simbólica del mapa: 3 pins con estado (actual / completado /
/// próximo) + 5 avatares con color (4 juntos sobre la parada actual, 1 "Val"
/// atrás viniendo en Uber). Aproximación del mapa SVG del mockup — iteramos
/// en pase futuro con MapKit o MapLibre y datos reales.
@MainActor
private struct GroupNightMapCard: View {
    private struct MapPin: Identifiable {
        let id = UUID()
        let x: CGFloat   // 0...1
        let y: CGFloat   // 0...1
        let label: String
        let state: GroupNightMapCard_PinState
    }

    private struct MapAvatar: Identifiable {
        let id = UUID()
        let x: CGFloat
        let y: CGFloat
        let color: Color
        let initials: String
        let note: String?
        let late: Bool
    }

    private let pins: [MapPin] = [
        .init(x: 0.52, y: 0.46, label: "Amor Miami", state: .current),
        .init(x: 0.28, y: 0.28, label: "El Patio",   state: .done),
        .init(x: 0.74, y: 0.70, label: "La Otra · 01:00", state: .next),
    ]

    private let avatars: [MapAvatar] = [
        .init(x: 0.49, y: 0.40, color: Color(red: 0.92, green: 0.72, blue: 0.28), initials: "S",   note: nil, late: false),
        .init(x: 0.56, y: 0.50, color: Color(red: 0.55, green: 0.40, blue: 0.95), initials: "M",   note: nil, late: false),
        .init(x: 0.45, y: 0.52, color: Color(red: 0.20, green: 0.90, blue: 0.40), initials: "J",   note: nil, late: false),
        .init(x: 0.36, y: 0.62, color: Color(red: 0.92, green: 0.92, blue: 0.98), initials: "D",   note: "Dani · 4 min", late: false),
        .init(x: 0.20, y: 0.80, color: Color(red: 1.00, green: 0.45, blue: 0.45), initials: "V",   note: "Val · Uber 12 min", late: true),
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // "Agua" + fondo
                LinearGradient(
                    colors: [
                        Color(red: 0.11, green: 0.06, blue: 0.18),
                        Color(red: 0.05, green: 0.03, blue: 0.09),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )

                // Agua simulada: diagonal fría
                Path { p in
                    p.move(to: CGPoint(x: proxy.size.width * 0.72, y: 0))
                    p.addLine(to: CGPoint(x: proxy.size.width, y: 0))
                    p.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height))
                    p.addLine(to: CGPoint(x: proxy.size.width * 0.6, y: proxy.size.height))
                    p.closeSubpath()
                }
                .fill(Color(red: 0.08, green: 0.18, blue: 0.26).opacity(0.6))

                // Streets (líneas finas cruzando)
                Path { p in
                    for i in stride(from: 0, through: 1, by: 0.2) {
                        p.move(to: CGPoint(x: 0, y: proxy.size.height * CGFloat(i)))
                        p.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height * CGFloat(i)))
                    }
                    for i in stride(from: 0, through: 1, by: 0.2) {
                        p.move(to: CGPoint(x: proxy.size.width * CGFloat(i), y: 0))
                        p.addLine(to: CGPoint(x: proxy.size.width * CGFloat(i), y: proxy.size.height))
                    }
                }
                .stroke(Color.white.opacity(0.05), lineWidth: 0.6)

                // Pins
                ForEach(pins) { pin in
                    MapPinView(label: pin.label, state: pin.state)
                        .position(x: proxy.size.width * pin.x, y: proxy.size.height * pin.y)
                }

                // Avatars
                ForEach(avatars) { av in
                    MapAvatarView(color: av.color, initials: av.initials, note: av.note, late: av.late)
                        .position(x: proxy.size.width * av.x, y: proxy.size.height * av.y)
                }

                // ETA ribbon abajo
                VStack {
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: "figure.walk")
                            .font(.system(size: 10, weight: .heavy))
                        Text("6 min caminando a La Otra · todos juntos salvo Val")
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .tracking(0.4)
                    }
                    .foregroundStyle(Color.white.opacity(0.78))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.black.opacity(0.55), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.1)))
                    .padding(10)
                }
            }
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white.opacity(0.08)))
    }
}

@MainActor
private struct MapPinView: View {
    let label: String
    let state: GroupNightMapCard_PinState

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(fill)
                    .frame(width: dot, height: dot)
                if state == .current {
                    Circle()
                        .stroke(Color.bpAmber.opacity(0.4), lineWidth: 2)
                        .frame(width: dot + 10, height: dot + 10)
                }
                if state == .done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundStyle(.black)
                }
            }
            Text(label)
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(labelColor)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Color.black.opacity(0.6), in: Capsule())
                .overlay(Capsule().strokeBorder(stroke, lineWidth: 0.6))
                .fixedSize()
        }
    }

    private var dot: CGFloat { state == .current ? 12 : 9 }
    private var fill: Color {
        switch state {
        case .current: return Color.bpAmber
        case .done:    return Color.bpGreen
        case .next:    return Color.white.opacity(0.6)
        }
    }
    private var labelColor: Color {
        switch state {
        case .current: return Color.bpAmberBright
        case .done:    return Color.bpGreen.opacity(0.9)
        case .next:    return Color.white.opacity(0.78)
        }
    }
    private var stroke: Color {
        switch state {
        case .current: return Color.bpAmber.opacity(0.4)
        case .done:    return Color.bpGreen.opacity(0.35)
        case .next:    return Color.white.opacity(0.15)
        }
    }
}

// Enum re-exportado como alias de scope — Swift no permite nested enum en
// un @MainActor private struct a referenciar desde fuera, así que lo
// elevamos a top-level private con un nombre con prefijo del dueño.
private enum GroupNightMapCard_PinState { case current, done, next }

// Re-escribimos el MapPin para usar el enum top-level
extension GroupNightMapCard {
    fileprivate static func _dummy_() {} // force module membership for extension
}

// Puente para el ForEach anterior (compilador necesita que ambos tipos coincidan)
// Tomamos el camino simple: redefinimos localmente.

@MainActor
private struct MapAvatarView: View {
    let color: Color
    let initials: String
    let note: String?
    let late: Bool

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [color, color.opacity(0.65)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 26, height: 26)
                    .overlay(
                        Circle().strokeBorder(late ? Color.bpDanger.opacity(0.9) : Color.white.opacity(0.8), lineWidth: 1.5)
                    )
                Text(initials)
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
            }
            if let note {
                Text(note)
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(late ? Color.bpDanger : Color.white.opacity(0.8))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color.black.opacity(0.6), in: Capsule())
                    .overlay(Capsule().strokeBorder(late ? Color.bpDanger.opacity(0.35) : Color.white.opacity(0.1), lineWidth: 0.6))
                    .fixedSize()
            }
        }
    }
}

// MARK: - Hype del grupo (eq bars + score 84)

@MainActor
private struct GroupNightHypeCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hype del grupo")
                .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                .tracking(2)
                .foregroundStyle(Color(red: 0.95, green: 0.55, blue: 0.85))

            HStack(alignment: .bottom, spacing: 8) {
                EqualizerBars()
                Text("84")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(Color.bpAmberBright)
            }

            // barra
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(
                            colors: [Color.bpAmber, Color.bpAmberBright],
                            startPoint: .leading, endPoint: .trailing))
                        .frame(width: proxy.size.width * 0.84)
                }
            }
            .frame(height: 4)

            Text("3 check-ins · 12 fotos · 2 rondas")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08)))
    }
}

/// 5 barritas estilo equalizer, con alturas distintas y animación sutil.
@MainActor
private struct EqualizerBars: View {
    @State private var pulse = false
    private let heights: [CGFloat] = [8, 14, 18, 11, 15]

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(heights.enumerated()), id: \.offset) { i, h in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.bpAmber)
                    .frame(width: 3, height: h * (pulse ? 1.0 : 0.65))
                    .animation(
                        .easeInOut(duration: 0.9)
                        .repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.12),
                        value: pulse
                    )
            }
        }
        .onAppear { pulse = true }
    }
}

// MARK: - Cuenta del grupo

@MainActor
private struct GroupNightTabCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Cuenta del grupo")
                .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                .tracking(2)
                .foregroundStyle(Color.white.opacity(0.65))

            Text("$118")
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            HStack(spacing: 4) {
                Text("Lo tuyo:")
                Text("$31").foregroundStyle(Color.bpAmberBright).fontWeight(.heavy)
                Text("· 4 personas").foregroundStyle(Color.white.opacity(0.5))
            }
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.72))
            .lineLimit(1)
            .minimumScaleFactor(0.75)

            Button { } label: {
                Text("Pagar mi parte")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.bpAmber, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08)))
    }
}

// MARK: - Poll (próxima parada · votación · cierra 00:30)

@MainActor
private struct GroupNightPollCard: View {
    @Binding var choice: Int

        // Mockup: La Otra 60%/3, Floyd 40%/2 — el usuario ya votó por La Otra.
    private var options: [GroupNightPollCard_Option] {
        [
            .init(name: "La Otra at Mad Wynwood", votes: choice == 0 ? 3 : 2, percentage: choice == 0 ? 0.60 : 0.40),
            .init(name: "Floyd (Downtown, Uber 15 min)", votes: choice == 1 ? 3 : 2, percentage: choice == 1 ? 0.60 : 0.40),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Próxima parada · votación")
                    .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                    .tracking(2.0)
                    .foregroundStyle(Color.bpAmber)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 9, weight: .heavy))
                    Text("cierra 00:30")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .tracking(0.8)
                }
                .foregroundStyle(Color.white.opacity(0.6))
            }

            ForEach(Array(options.enumerated()), id: \.offset) { idx, opt in
                PollOptionRow(
                    option: opt,
                    isWinner: idx == choice,
                    onTap: { choice = idx }
                )
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08)))
    }
}

@MainActor
private struct PollOptionRow: View {
    let option: GroupNightPollCard_Option
    let isWinner: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .leading) {
                // barra de fondo
                GeometryReader { proxy in
                    Capsule()
                        .fill(isWinner ? Color.bpAmber.opacity(0.18) : Color.white.opacity(0.05))
                        .frame(width: proxy.size.width * option.percentage)
                }
                HStack {
                    Text(option.name)
                        .font(.system(size: 13, weight: isWinner ? .heavy : .semibold, design: .rounded))
                        .foregroundStyle(isWinner ? Color.bpAmberBright : Color.white.opacity(0.85))
                    Spacer()
                    Text("\(option.votes)")
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .foregroundStyle(isWinner ? Color.bpAmber : Color.white.opacity(0.5))
                }
                .padding(.horizontal, 12)
            }
            .frame(height: 36)
            .background(Color.white.opacity(0.03), in: Capsule())
            .overlay(Capsule().strokeBorder(isWinner ? Color.bpAmber.opacity(0.35) : Color.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }
}

// Puente al tipo privado del padre (los tipos nested de un struct @MainActor
// private no son visibles al PollOptionRow a pesar del `fileprivate` por un
// quirk del compilador — usamos un typealias/wrapper top-level).
private struct GroupNightPollCard_Option {
    let name: String
    let votes: Int
    let percentage: CGFloat
}
// (removed dead _migrate helper — the Option/GroupNightPollCard_Option split
// was a leftover from an earlier draft; the Card uses Option directly now)

// MARK: - Chat corto con reactions

@MainActor
private struct GroupNightChatCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Chat del grupo")
                    .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                    .tracking(2.0)
                    .foregroundStyle(Color.white.opacity(0.6))
                Spacer()
                Text("5 participantes")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.4))
            }

            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color(red: 1.0, green: 0.42, blue: 0.42), Color(red: 0.6, green: 0.18, blue: 0.18)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 34, height: 34)
                    Text("S")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(.black)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Santi")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                        Text("23:38")
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.4))
                    }
                    Text("la terraza está vacía, vengan 🔥")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        reactionChip("🔥", count: 4)
                        reactionChip("👀", count: 2)
                    }
                    .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }

            // input simulado
            HStack(spacing: 8) {
                Text("Escribí al grupo…")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.35))
                Spacer()
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Color.bpAmber)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.08)))
        }
        .padding(12)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08)))
    }

    private func reactionChip(_ emoji: String, count: Int) -> some View {
        HStack(spacing: 4) {
            Text(emoji).font(.system(size: 11))
            Text("\(count)")
                .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.75))
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Color.white.opacity(0.08), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1)))
    }
}

// MARK: - Momentos (fotos)

@MainActor
private struct GroupNightMomentsCard: View {
    private let moments: [(gradientA: Color, gradientB: Color, caption: String)] = [
        (Color(red: 0.55, green: 0.14, blue: 0.42), Color(red: 0.15, green: 0.03, blue: 0.1), "Amor · 23:12"),
        (Color(red: 0.22, green: 0.14, blue: 0.42), Color(red: 0.05, green: 0.03, blue: 0.15), "Amor · 23:21"),
        (Color(red: 0.70, green: 0.42, blue: 0.12), Color(red: 0.20, green: 0.08, blue: 0.03), "El Patio · 22:48"),
        (Color(red: 0.12, green: 0.42, blue: 0.42), Color(red: 0.03, green: 0.1, blue: 0.1), "El Patio · 22:30"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Momentos del grupo")
                    .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                    .tracking(2.0)
                    .foregroundStyle(Color.white.opacity(0.6))
                Spacer()
                Text("12 fotos")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.4))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(moments.enumerated()), id: \.offset) { _, m in
                        VStack(alignment: .leading, spacing: 6) {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(LinearGradient(
                                    colors: [m.gradientA, m.gradientB],
                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(Color.white.opacity(0.1))
                                )
                                .frame(width: 102, height: 128)
                            Text(m.caption)
                                .font(.system(size: 9.5, design: .monospaced))
                                .tracking(0.4)
                                .foregroundStyle(Color.white.opacity(0.55))
                        }
                    }

                    // CTA: añadir foto
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.bpAmber.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color.bpAmber.opacity(0.35), style: StrokeStyle(lineWidth: 1.4, dash: [6, 4]))
                            )
                            .overlay(
                                VStack(spacing: 4) {
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 20, weight: .heavy))
                                        .foregroundStyle(Color.bpAmber)
                                    Text("añadir")
                                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                                        .tracking(1.2)
                                        .foregroundStyle(Color.bpAmber)
                                }
                            )
                            .frame(width: 102, height: 128)
                        Text("compartí al grupo")
                            .font(.system(size: 9.5, design: .monospaced))
                            .tracking(0.4)
                            .foregroundStyle(Color.bpAmber.opacity(0.75))
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08)))
    }
}

// MARK: - SOS button (ancho, al fondo — nunca enterrado en un menú)

@MainActor
private struct GroupNightSOSButton: View {
    @State private var holdProgress: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Si algo se puso raro")
                .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                .tracking(2.0)
                .foregroundStyle(Color.bpDanger.opacity(0.9))

            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(Color.bpDanger)
                VStack(alignment: .leading, spacing: 2) {
                    Text("SOS grupo")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Mantené para avisar al grupo y a seguridad del venue")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Color.bpDanger.opacity(0.85))
            }
            .padding(14)
            .background(
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.bpDanger.opacity(0.08))
                    GeometryReader { proxy in
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.bpDanger.opacity(0.25))
                            .frame(width: proxy.size.width * holdProgress)
                    }
                }
            )
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bpDanger.opacity(0.4)))
            .gesture(
                LongPressGesture(minimumDuration: 1.4)
                    .onChanged { _ in
                        withAnimation(.linear(duration: 1.4)) { holdProgress = 1 }
                    }
                    .onEnded { _ in
                        // Stub: en producción esto llamaría a SafetyService
                        // (notificación al trip + ping a security del venue).
                        withAnimation(.easeOut(duration: 0.3)) { holdProgress = 0 }
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { _ in
                        withAnimation(.easeOut(duration: 0.3)) { holdProgress = 0 }
                    }
            )
        }
    }
}
