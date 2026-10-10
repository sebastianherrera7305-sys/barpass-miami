import SwiftUI

// VenuePulseView — pantalla 10 del artifact 294356f9 ("Venue con pulso").
//
// Traduce la sección "2 · La noche en vivo · Venue con pulso" (líneas
// 895–972 del mockup) al kit nativo. Reemplaza visualmente la vieja
// VenueDetailView (ficha estática) por una pantalla viva: cómo está AHORA
// un venue — curva de lleno, fila, qué suena, amigos adentro, lo que dice
// la gente hoy y el "take" de Remy con la mejor hora para entrar.
//
// Estilo heredado de OnboardingV2Flow (artifact 294356f9):
//   display  → .system(design: .rounded, weight: .black)
//   accent   → .system(design: .serif).italic()
//   eyebrow  → .system(design: .monospaced).tracking
// Fondo warm vignette + grain + eye-asset "CityArtMiami" al tope, en modo
// sutil (opacity 0.35) para no competir con la densidad de datos.
//
// Limitaciones conocidas (declaradas también en `limitations`):
//   · Los datos vivos (ocupación 78%, fila 20 min, voces 23:30/23:12/22:50,
//     "Mía y Jules adentro") son LITERALES del mockup. Cuando se cablee a
//     Supabase + venue-pulse edge function, el inicializador podrá recibir
//     un modelo real; por ahora el entry point toma un nombre opcional y
//     usa los datos del mockup.
//   · No se registra el archivo en el pbxproj (lo hace quien integra).
//   · El rayo-sol SVG del mockup (sun con 36 polígonos de colores) se
//     aproxima con el asset existente "CityArtMiami" + un cono amber en el
//     tope — equivalente visual sin cargar un SVG custom.
//   · No consume VenueStore ni RepositoryDependencies; sólo @EnvironmentObject
//     AppState para los callbacks de cerrar / Skip the Line (optional).
//   · Las fuentes del mockup (Bebas Neue, Instrument Serif, Courier Prime)
//     se aproximan con `.system(design:)` — mismo criterio que OnboardingV2.

@MainActor
struct VenuePulseView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let venueName: String
    let subtitleAccent: String
    let openUntil: String
    let fillPercent: Int

    init(
        venueName: String = "Club",
        subtitleAccent: String = "Space",
        openUntil: String = "04:00",
        fillPercent: Int = 78
    ) {
        self.venueName = venueName
        self.subtitleAccent = subtitleAccent
        self.openUntil = openUntil
        self.fillPercent = fillPercent
    }

    var body: some View {
        ZStack {
            VPulseBackground()

            VStack(spacing: 0) {
                VPulseStatusBar()
                VPulseNavBar(title: "\(venueName.uppercased()) \(subtitleAccent.uppercased())",
                             onBack: { dismiss() })

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VPulseHeader(
                            venueName: venueName,
                            accent: subtitleAccent,
                            openUntil: openUntil,
                            fillPercent: fillPercent,
                            nowLabel: "23:41"
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 14)

                        VPulseOccupancyCard()
                            .padding(.horizontal, 20)

                        VPulseFriendsCard()
                            .padding(.horizontal, 20)

                        VPulseVoicesSection()
                            .padding(.top, 2)

                        VPulseRemyTake()
                            .padding(.horizontal, 20)
                            .padding(.top, 4)

                        Spacer().frame(height: 110) // room for sticky CTA
                    }
                    .padding(.bottom, 20)
                }
            }

            VStack {
                Spacer()
                VPulseStickyCTA()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
        }
        .preferredColorScheme(.dark)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - Background

@MainActor
private struct VPulseBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.015, blue: 0.04).ignoresSafeArea()

            // The Miami eye at the top, same asset as OnboardingV2 — pushed
            // up high and dimmed, so it reads as a halo behind the big
            // percentage, not as a hero.
            GeometryReader { proxy in
                Image("CityArtMiami")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width * 2.4,
                           height: proxy.size.width * 2.4)
                    .position(x: proxy.size.width * 0.5,
                              y: proxy.size.height * -0.12)
                    .opacity(0.35)
            }
            .ignoresSafeArea()

            // Warm vignette halation
            RadialGradient(
                colors: [.clear, Color(red: 0.27, green: 0.09, blue: 0).opacity(0.42)],
                center: UnitPoint(x: 0.5, y: 0.32),
                startRadius: 160, endRadius: 700
            )
            .ignoresSafeArea()
            .blendMode(.multiply)

            // Fade to black below the fold so content reads cleanly
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.88), Color.black],
                startPoint: UnitPoint(x: 0.5, y: 0.18),
                endPoint: .bottom
            )
            .ignoresSafeArea()

            GrainTexture(opacity: 0.12)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Status bar + nav bar (mockup chrome, kept minimal)

@MainActor
private struct VPulseStatusBar: View {
    var body: some View {
        HStack {
            Text("23:41")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(Color.white.opacity(0.75))
            Spacer()
            Text("SOS")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(Color.bpAmber)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.bpAmber.opacity(0.3)))
            Text("63%")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(Color.white.opacity(0.75))
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}

@MainActor
private struct VPulseNavBar: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.06), in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain)

            Spacer()

            Text(title)
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .tracking(3.2)
                .foregroundStyle(Color.white.opacity(0.78))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer()

            Button(action: {}) {
                Text("Compartir")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(Color.bpAmber)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
}

// MARK: - Header: ABIERTO · nombre + accent · 78% lleno

@MainActor
private struct VPulseHeader: View {
    let venueName: String
    let accent: String
    let openUntil: String
    let fillPercent: Int
    let nowLabel: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text("ABIERTO")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.bpGreen)
                        .shadow(color: Color.bpGreen.opacity(0.45), radius: 6)

                    Text("\(nowLabel) · cierra \(openUntil)")
                        .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                        .tracking(1.6)
                        .foregroundStyle(Color.white.opacity(0.55))
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(venueName)
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .tracking(-0.8)
                        .foregroundStyle(.white)
                    Text(accent)
                        .font(.system(size: 32, design: .serif).italic())
                        .foregroundStyle(Color.bpAmberBright)
                }
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(fillPercent)%")
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .tracking(-1.2)
                    .foregroundStyle(Color.bpAmber)
                    .shadow(color: Color.bpAmber.opacity(0.4), radius: 10)
                Text("lleno")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(Color.white.opacity(0.55))
            }
        }
    }
}

// MARK: - Occupancy card (curve + axis + chips)

@MainActor
private struct VPulseOccupancyCard: View {
    // Hours 22..04 → percentages matching the "pico 01:30–03:00" peak.
    // Index of "ahora" (23 bucket) is 1.
    private let hours: [String] = ["22", "23", "ahora", "01", "02", "03", "04"]
    private let fills: [CGFloat] = [0.28, 0.46, 0.78, 0.90, 1.0, 0.95, 0.58]
    private let nowIndex: Int = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Cómo se llena hoy")
                    .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(Color.white.opacity(0.65))
                Spacer()
                Text("pico 01:30–03:00")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(Color.bpAmber)
            }

            VPulseBarChart(fills: fills, nowIndex: nowIndex)
                .frame(height: 86)

            VPulseAxisRow(labels: hours, highlightIndex: nowIndex)

            VPulseChipRow(chips: [
                .init(icon: "clock", text: "fila 20 min", amber: false),
                .init(icon: "waveform", text: "sonando techno", amber: false),
                .init(icon: "slider.horizontal.3", text: "Mejor hora: ahora", amber: true),
            ])
            .padding(.top, 4)
        }
        .padding(14)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.08)))
    }
}

@MainActor
private struct VPulseBarChart: View {
    let fills: [CGFloat]
    let nowIndex: Int

    var body: some View {
        GeometryReader { geo in
            let barCount = fills.count
            let spacing: CGFloat = 10
            let totalSpacing = spacing * CGFloat(barCount - 1)
            let barWidth = max((geo.size.width - totalSpacing) / CGFloat(barCount), 10)
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(fills.indices, id: \.self) { i in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(barFill(i))
                            .frame(width: barWidth,
                                   height: max(geo.size.height * fills[i], 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(
                                        i == nowIndex ? Color.bpAmberBright : Color.clear,
                                        lineWidth: 1
                                    )
                            )
                            .shadow(
                                color: i == nowIndex ? Color.bpAmber.opacity(0.55) : .clear,
                                radius: 8
                            )
                    }
                }
            }
        }
    }

    private func barFill(_ i: Int) -> LinearGradient {
        if i == nowIndex {
            return LinearGradient(
                colors: [Color.bpAmberBright, Color.bpAmber],
                startPoint: .top, endPoint: .bottom
            )
        }
        if i < nowIndex {
            return LinearGradient(
                colors: [Color.white.opacity(0.22), Color.white.opacity(0.08)],
                startPoint: .top, endPoint: .bottom
            )
        }
        return LinearGradient(
            colors: [Color.bpAmber.opacity(0.55), Color.bpAmber.opacity(0.22)],
            startPoint: .top, endPoint: .bottom
        )
    }
}

@MainActor
private struct VPulseAxisRow: View {
    let labels: [String]
    let highlightIndex: Int

    var body: some View {
        HStack(spacing: 10) {
            ForEach(labels.indices, id: \.self) { i in
                Text(labels[i])
                    .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(i == highlightIndex ? Color.bpAmber : Color.white.opacity(0.42))
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct VPulseChip: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
    let amber: Bool
}

@MainActor
private struct VPulseChipRow: View {
    let chips: [VPulseChip]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(chips) { c in
                HStack(spacing: 5) {
                    Image(systemName: c.icon)
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(c.amber ? Color.bpAmber : Color.white.opacity(0.75))
                    Text(c.text)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(c.amber ? Color.bpAmberBright : Color.white.opacity(0.78))
                        .lineLimit(1)
                }
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(
                    c.amber
                        ? Color.bpAmber.opacity(0.18)
                        : Color.white.opacity(0.06),
                    in: Capsule()
                )
                .overlay(
                    Capsule().strokeBorder(
                        c.amber ? Color.bpAmber.opacity(0.4) : Color.white.opacity(0.1)
                    )
                )
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Friends card (avstack · texto · Ir)

@MainActor
private struct VPulseFriendsCard: View {
    var body: some View {
        HStack(spacing: 12) {
            // Avatar stack — two overlapping circles from the mockup
            HStack(spacing: -10) {
                ForEach(0..<2, id: \.self) { i in
                    Circle()
                        .fill(LinearGradient(
                            colors: [
                                Color(red: 0.42, green: 0.18, blue: 0.08),
                                Color(red: 0.18, green: 0.07, blue: 0.04)
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 36, height: 36)
                        .overlay(Circle().strokeBorder(Color.black, lineWidth: 2))
                        .overlay(
                            Text(i == 0 ? "M" : "J")
                                .font(.system(size: 14, weight: .black, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.9))
                        )
                        .zIndex(Double(2 - i))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Mía y Jules adentro · desde 23:05")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("+ 6 personas que conoces estuvieron este mes")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .lineLimit(2)
            }

            Spacer(minLength: 6)

            Text("Ir")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .tracking(2)
                .foregroundStyle(.black)
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(Color.bpAmber, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.bpAmberBright, lineWidth: 1))
        }
        .padding(12)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08)))
    }
}

// MARK: - Voices section ("Lo que dice la gente hoy")

@MainActor
private struct VPulseVoicesSection: View {
    private let voices: [VPulseVoice] = [
        .init(stamp: "23:30 · Leo",
              body: "\"terraza abierta, adentro ya está lleno\""),
        .init(stamp: "23:12",
              body: "\"$18 el trago, cover $20 antes de la 1\""),
        .init(stamp: "22:50",
              body: "\"la fila va rápido con el pase\""),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Lo que dice la gente hoy")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Text("14 hoy")
                    .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(Color.bpAmber)
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(voices) { v in
                        VPulseVoiceCard(voice: v)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 2)
            }
        }
    }
}

private struct VPulseVoice: Identifiable {
    let id = UUID()
    let stamp: String
    let body: String
}

@MainActor
private struct VPulseVoiceCard: View {
    let voice: VPulseVoice

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(voice.stamp)
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(Color.white.opacity(0.5))
            Text(voice.body)
                .font(.system(size: 13, design: .serif).italic())
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(3)
        }
        .padding(12)
        .frame(width: 220, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08)))
    }
}

// MARK: - Remy's amber "take"

@MainActor
private struct VPulseRemyTake: View {
    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color.bpAmber)
                    .frame(width: 32, height: 32)
                Text("R")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Remy")
                    .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(Color.white.opacity(0.65))

                // Mockup: "Entras en tu $31 si pedís 1 trago. Con Skip the Line
                // entras a las 00:45 sin fila." — ajustado a copy neutro
                // (sin voseo) por la regla de UI del proyecto.
                (
                    Text("Entrás en tu ").foregroundStyle(Color.white.opacity(0.85)) +
                    Text("$31").font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white) +
                    Text(" si pedís 1 trago. Con Skip the Line entrás ")
                        .foregroundStyle(Color.white.opacity(0.85)) +
                    Text("a las 00:45 sin fila.").font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                )
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color.bpAmber.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bpAmber.opacity(0.35)))
    }
}

// MARK: - Sticky bottom CTA ("Abrir cuenta" + "Skip the Line · $25")

@MainActor
private struct VPulseStickyCTA: View {
    var body: some View {
        HStack(spacing: 10) {
            Button(action: {}) {
                Text("Abrir cuenta")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.18)))
            }
            .buttonStyle(.plain)

            Button(action: {}) {
                HStack(spacing: 6) {
                    Text("Skip the Line")
                    Text("·").foregroundStyle(.black.opacity(0.5))
                    Text("$25")
                }
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.bpAmber, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bpAmberBright, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.black.opacity(0.55))
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(.ultraThinMaterial)
                )
        )
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white.opacity(0.08)))
    }
}

// MARK: - Preview

#Preview {
    VenuePulseView()
        .environmentObject(AppState())
}
