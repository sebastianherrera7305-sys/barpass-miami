import SwiftUI

// OpenTabV2View — pantalla "Cuenta abierta" del artifact v17.1
// (líneas 1620–1771, grupo "Venue y compra"). Es el sheet que ve el usuario
// cuando tiene una cuenta activa en un venue: lo que lleva gastado él vs lo
// que lleva el grupo, el código corto que el bartender escanea para sumar
// consumos a su tab, y la lista de consumos cargados hasta ahora.
//
// Lo que lee del mockup:
// - Nav de sheet ("Tu cuenta" · "Cerrar", sin flecha de back).
// - Eyebrow live con punto pulsante: "Cuenta abierta · Bodega Taqueria
//   y Tequila".
// - Card amber "Lo tuyo" con el gran total propio ($34.00), total del grupo
//   ($118.00 · 4 personas), y una stack de 4 avatars pastel.
// - CTA primaria "Mostrar código" + línea mono con el código corto "4F7Q".
// - Section header "Consumos" y 4 filas de glass con emoji/texto/precio;
//   el 3er row va dimmed porque es un trago que invitó Dani.
// - Fine print mono: "Tope aprobado: $60 · el bartender escanea tu código".
//
// Estilo: fondo Miami eye `bd-dim` (eye casi plano, scale 2.4, opacity 0.35)
// + warm RadialGradient vignette + fade mask + GrainTexture 0.13. Tipografía
// black rounded para números, serif italic para el acento del gran total,
// mono tracked para eyebrows / códigos / tiempos. Cards blancas 0.04 con
// strokeBorder 0.08 (y la mine-card amber 0.10 con stroke 0.35).
//
// Limitaciones conocidas:
// - Data hard-coded del mockup; no se wirea aún a VenueStore ni a un
//   `openTabs` endpoint — ese es un pass siguiente cuando exista el schema.
// - "Mostrar código" es visualmente un CTA pero no abre todavía el QR
//   fullscreen (reusará QRConfirmView del PriorityEntry hub). Haptic + log.
// - Los 4 avatars son placeholders de círculos de color pastel; cuando
//   haya `FriendPresence` real conectado, se reemplazan por el avatar de
//   cada miembro del trip.
// - El punto "live" pulsa con un .repeatForever simple; no es tan sutil
//   como la animación del artifact pero cumple el rol de señal activa.

@MainActor
public struct OpenTabV2View: View {
    @Environment(\.dismiss) private var dismiss

    // --- Mockup data (ver limitaciones) ---
    private let venueName = "Bodega Taqueria y Tequila"
    private let myTotal = "$34.00"
    private let groupTotal = "$118.00"
    private let groupSize = 4
    private let joinCode = "4F7Q"
    private let cap = "$60"

    private let consumos: [OpenTabV2Item] = [
        .init(emoji: "🍸", title: "Select Cocktails ×2", subtitle: "hace 20 min", amount: "$20.00", dimmed: false),
        .init(emoji: "🍺", title: "Well Drinks",         subtitle: "hace 35 min", amount: "$8.00",  dimmed: false),
        .init(emoji: "🥃", title: "Patron Shots",        subtitle: "hace 50 min · de Dani", amount: "$7.00", dimmed: true),
        .init(emoji: "🍸", title: "Draft Beer & Margarita", subtitle: "hace 1 h", amount: "$6.00", dimmed: false),
    ]

    private let avatars: [Color] = [
        Color(red: 0.92, green: 0.72, blue: 0.28),   // amber (yo)
        Color(red: 0.55, green: 0.40, blue: 0.95),   // morado
        Color(red: 0.20, green: 0.90, blue: 0.40),   // verde
        Color(red: 0.92, green: 0.92, blue: 0.95),   // bone/white
    ]

    @State private var pulse = false

    public init() {}

    public var body: some View {
        ZStack {
            OpenTabV2Background()

            VStack(spacing: 0) {
                // Deja ~70pt libres bajo el status bar — mismo "ritmo" que
                // Onboarding y RemyLive, para que el sheet respire igual.
                Spacer().frame(height: 70)

                navBar
                    .padding(.horizontal, 16)
                    .padding(.top, 2)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        liveEyebrow
                            .padding(.horizontal, 16)
                            .padding(.top, 14)

                        mineCard
                            .padding(.horizontal, 16)

                        codeBlock
                            .padding(.horizontal, 16)
                            .padding(.top, 2)

                        Text("Consumos")
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.top, 4)

                        consumosCard
                            .padding(.horizontal, 16)

                        Text("Tope aprobado: \(cap) · el bartender escanea tu código")
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .tracking(0.6)
                            .foregroundStyle(Color.white.opacity(0.42))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, 16)
                            .padding(.top, 6)

                        Spacer(minLength: 24)
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    // MARK: - Nav bar (sheet style: titulo + Cerrar)

    private var navBar: some View {
        HStack(spacing: 10) {
            Text("Tu cuenta")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.7), radius: 4, y: 1)

            Spacer()

            Button {
                tapHaptic()
                dismiss()
            } label: {
                Text("Cerrar")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(0.4)
                    .foregroundStyle(Color.bpAmber)
            }
            .buttonStyle(.plain)
        }
        .frame(height: 32)
    }

    // MARK: - Live eyebrow

    private var liveEyebrow: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(Color.bpAmber)
                .frame(width: 7, height: 7)
                .overlay(
                    Circle()
                        .fill(Color.bpAmber)
                        .blur(radius: 4)
                        .opacity(pulse ? 0.85 : 0.3)
                )
                .scaleEffect(pulse ? 1.1 : 0.9)

            Text("Cuenta abierta · \(venueName)")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(Color.bpAmberBright)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    // MARK: - Mine card ("Lo tuyo" + avatars)

    private var mineCard: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Lo tuyo")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .tracking(2.0)
                    .foregroundStyle(Color.bpAmberBright.opacity(0.85))

                Text(myTotal)
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: Color.bpAmber.opacity(0.25), radius: 10, y: 2)

                (
                    Text("El grupo va ")
                        .foregroundStyle(Color.white.opacity(0.75))
                    + Text(groupTotal)
                        .font(.system(size: 12.5, weight: .black, design: .rounded))
                        .foregroundStyle(Color.bpAmberBright)
                    + Text(" · ")
                        .foregroundStyle(Color.white.opacity(0.55))
                    + Text("\(groupSize) personas")
                        .font(.system(size: 12, design: .serif).italic())
                        .foregroundStyle(Color.white.opacity(0.85))
                )
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            OpenTabV2AvatarStack(colors: avatars)
                .padding(.top, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.bpAmber.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.bpAmber.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Code block (CTA + mono string)

    private var codeBlock: some View {
        VStack(spacing: 10) {
            Button {
                tapHaptic()
            } label: {
                Text("Mostrar código")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(
                                LinearGradient(
                                    colors: [Color.bpAmberBright, Color.bpAmber],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                    )
                    .shadow(color: Color.bpAmber.opacity(0.35), radius: 14, y: 6)
            }
            .buttonStyle(.plain)

            HStack(spacing: 0) {
                Text("Código para sumar gente · ")
                    .foregroundStyle(Color.white.opacity(0.55))
                Text(joinCode)
                    .foregroundStyle(Color.bpAmberBright)
                    .tracking(2.0)
            }
            .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - Consumos card

    private var consumosCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(consumos.enumerated()), id: \.offset) { idx, item in
                OpenTabV2Row(item: item)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                if idx < consumos.count - 1 {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 1)
                        .padding(.leading, 14 + 32 + 10)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func tapHaptic() {
        #if canImport(UIKit)
        let g = UIImpactFeedbackGenerator(style: .light)
        g.impactOccurred()
        #endif
    }
}

// MARK: - Row data + view

private struct OpenTabV2Item {
    let emoji: String
    let title: String
    let subtitle: String
    let amount: String
    let dimmed: Bool
}

@MainActor
private struct OpenTabV2Row: View {
    let item: OpenTabV2Item

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(item.dimmed ? 0.03 : 0.06))
                    .frame(width: 32, height: 32)
                Text(item.emoji)
                    .font(.system(size: 16))
                    .opacity(item.dimmed ? 0.55 : 1)
            }
            .overlay(
                Circle().strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(item.dimmed ? Color.white.opacity(0.55) : .white)
                Text(item.subtitle)
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(Color.white.opacity(item.dimmed ? 0.4 : 0.55))
            }

            Spacer(minLength: 8)

            Text(item.amount)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(item.dimmed ? Color.white.opacity(0.45) : .white)
        }
    }
}

// MARK: - Avatar stack (overlapping circles)

@MainActor
private struct OpenTabV2AvatarStack: View {
    let colors: [Color]
    private let size: CGFloat = 30
    private let overlap: CGFloat = 10

    var body: some View {
        HStack(spacing: -overlap) {
            ForEach(Array(colors.enumerated()), id: \.offset) { idx, c in
                ZStack {
                    Circle()
                        .fill(c)
                        .frame(width: size, height: size)
                    // Mini "cara": una boca sutil para evitar un disco plano.
                    Circle()
                        .trim(from: 0.05, to: 0.20)
                        .stroke(Color.black.opacity(0.35), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                        .frame(width: size * 0.55, height: size * 0.55)
                        .rotationEffect(.degrees(90))
                        .offset(y: 1.5)
                }
                .overlay(
                    Circle()
                        .strokeBorder(Color(red: 0.06, green: 0.04, blue: 0.10), lineWidth: 2)
                )
                .zIndex(Double(colors.count - idx))
            }
        }
    }
}

// MARK: - Background (Miami eye bd-dim + warm vignette + grain)

@MainActor
private struct OpenTabV2Background: View {
    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.015, blue: 0.04).ignoresSafeArea()

            // bd-dim: el eye está casi plano arriba, muy sutil.
            GeometryReader { proxy in
                Image("CityArtMiami")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width * 2.4,
                           height: proxy.size.width * 2.4)
                    .position(x: proxy.size.width * 0.5,
                              y: proxy.size.height * -0.35)
                    .opacity(0.35)
            }
            .ignoresSafeArea()

            RadialGradient(
                colors: [.clear, Color(red: 0.27, green: 0.09, blue: 0).opacity(0.40)],
                center: UnitPoint(x: 0.5, y: 0.28),
                startRadius: 180, endRadius: 720
            )
            .ignoresSafeArea()
            .blendMode(.multiply)

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.92), Color.black],
                startPoint: UnitPoint(x: 0.5, y: 0.18),
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // GrainTexture ya existe en el bundle (ver OnboardingV2Flow).
            GrainTexture(opacity: 0.13)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}

#Preview {
    OpenTabV2View()
}
