import SwiftUI

// GamesMissionsV2View — Pantalla "Juegos y misiones" del artifact v17.1
// (grupo "Cuenta y seguridad", líneas 2587-2745 del mockup).
//
// Qué muestra:
//   · Header + eyebrow de temporada ("Temporada octubre · termina en 22 días").
//   · Podium "La liga de tu gente" con 3 posiciones: Mía 1°, Tú 2°, Jules 3°.
//     El del medio (Tú) es más grande, como en el mockup.
//   · Tarjeta de predicción abierta ("¿A qué hora Club Space llega al 90%?")
//     con 4 pills de respuesta — una seleccionada — y pistas sociales
//     ("Mía dice 01:30 · Dani 00:30").
//   · Misión de grupo en vivo con barra de progreso 4/5 + premio.
//   · Sección "Trivia de barra" — card de propuesta con CTA "Me apunto".
//   · Sección "Desbloqueos del avatar" — 3 tiles horizontales (gorra ganada,
//     cadena bloqueada por puntos, outfit bloqueado por diversidad de venues).
//
// Estilo: idéntico a RemyLiveView — fondo Miami eye + warm vignette + grain,
// tipografía black rounded / serif italic / mono tracked, cards
// Color.white.opacity(0.04) con stroke 0.08, acento amber.
//
// Limitaciones conocidas:
//   · Toda la data (nombres, puntajes, progreso, premios) es literal del
//     mockup. No se conecta todavía a un GamesStore / TripStore / AppState.
//   · Los avatares son aproximaciones SwiftUI (círculo + iniciales + accent
//     ring), no un port de los SVG del mockup — reemplazables cuando el
//     sistema de avatares real exista.
//   · "Me apunto" (trivia), tap en pills de predicción y tiles de avatar
//     son no-op con haptic liviano. El wiring real a trivia Live y a la
//     tabla de predicciones es un follow-up.
//   · El status bar fake (23:41 · SOS · 63%) se dibuja porque la vista es
//     una captura "en vivo"; en producción iOS pinta el suyo.

@MainActor
struct GamesMissionsV2View: View {
    @Environment(\.dismiss) private var dismiss

    @State private var predictionSelection: Int = 1  // "01:00"

    private let predictionPills: [String] = ["00:30", "01:00", "01:30", "02:00+"]

    var body: some View {
        ZStack {
            GamesMissionsBackground()

            VStack(spacing: 0) {
                fakeStatusBar
                navBar

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                            .padding(.horizontal, 22)
                            .padding(.top, 10)

                        podiumCard
                            .padding(.horizontal, 20)

                        predictionCard
                            .padding(.horizontal, 20)

                        groupMissionCard
                            .padding(.horizontal, 20)

                        sectionHeader(title: "Trivia de barra",
                                      action: "Club Space · 00:30")
                            .padding(.horizontal, 22)
                            .padding(.top, 4)

                        triviaCard
                            .padding(.horizontal, 20)

                        sectionHeader(title: "Desbloqueos del avatar",
                                      action: "2 / 6")
                            .padding(.horizontal, 22)
                            .padding(.top, 4)

                        unlocksRow
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)
                    }
                    .padding(.top, 14)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Status bar fake

    private var fakeStatusBar: some View {
        HStack {
            Text("23:41")
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.9))
            Spacer()
            HStack(spacing: 8) {
                Text("SOS")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(Color.bpAmber)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.bpAmber.opacity(0.3)))
                Text("63%")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.85))
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
    }

    // MARK: - Nav bar

    private var navBar: some View {
        HStack {
            Text("Juegos")
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Cerrar")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.bpAmberBright)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
    }

    // MARK: - Header (eyebrow + title)

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.bpAmberBright)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().fill(Color.bpAmberBright).blur(radius: 4).opacity(0.6))
                Text("TEMPORADA OCTUBRE · TERMINA EN 22 DÍAS")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .tracking(1.8)
                    .foregroundStyle(Color.bpAmberBright)
            }

            (
                Text("La liga de ")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                + Text("tu gente")
                    .font(.system(size: 24, design: .serif).italic())
                    .foregroundStyle(Color.bpAmberBright)
            )
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Podium

    private var podiumCard: some View {
        HStack(alignment: .bottom, spacing: 10) {
            podiumSlot(
                name: "Mía",
                points: "2.310",
                subline: nil,
                color: Color(red: 0.55, green: 0.4, blue: 0.95), // purple
                initial: "M",
                size: 54,
                isYou: false,
                rank: "1°"
            )

            podiumSlot(
                name: "Tú · 2°",
                points: "1.240",
                subline: "+175 anoche",
                color: Color.bpAmber,
                initial: "S",
                size: 72,
                isYou: true,
                rank: nil
            )

            podiumSlot(
                name: "Jules",
                points: "980",
                subline: nil,
                color: Color.bpGreen,
                initial: "J",
                size: 54,
                isYou: false,
                rank: "3°"
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func podiumSlot(name: String,
                            points: String,
                            subline: String?,
                            color: Color,
                            initial: String,
                            size: CGFloat,
                            isYou: Bool,
                            rank: String?) -> some View {
        VStack(spacing: 6) {
            GamesAvatar(color: color, initial: initial, size: size, ringAccent: isYou)
                .overlay(alignment: .topTrailing) {
                    if let rank {
                        Text(rank)
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(color))
                            .offset(x: 2, y: -2)
                    }
                }

            Text(name)
                .font(.system(size: isYou ? 13 : 11.5, weight: .heavy, design: .rounded))
                .foregroundStyle(isYou ? Color.bpAmberBright : .white)
                .lineLimit(1)

            Text(points)
                .font(.system(size: isYou ? 15 : 13, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            if let subline {
                Text(subline)
                    .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(Color.bpGreen)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Prediction card (glass amber)

    private var predictionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Color.bpAmberBright)
                    Text("PREDICCIÓN ABIERTA · EN JUEGO 50 BPX")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .tracking(1.6)
                        .foregroundStyle(Color.bpAmberBright)
                }
                Spacer()
                Text("resuelve 01:00")
                    .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.6))
            }

            Text("¿A qué hora Club Space llega al 90%?")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 7) {
                ForEach(Array(predictionPills.enumerated()), id: \.offset) { idx, label in
                    PredictionPill(label: label,
                                   selected: idx == predictionSelection) {
                        actionLog("pred_\(label)")
                        withAnimation(.easeOut(duration: 0.18)) {
                            predictionSelection = idx
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            Text("Se resuelve con check-ins reales · Mía dice 01:30 · Dani 00:30")
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.bpAmber.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.bpAmber.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Group mission

    private var groupMissionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Misión de grupo · esta noche")
                    .font(.system(size: 14.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Text("en vivo")
                    .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(Color.bpGreen)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(Color.bpGreen.opacity(0.14)))
                    .overlay(Capsule().strokeBorder(Color.bpGreen.opacity(0.4), lineWidth: 1))
            }

            Text("Los 5 en la misma foto antes de la 01:00")
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.72))

            HStack(spacing: 10) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                        Capsule()
                            .fill(LinearGradient(
                                colors: [Color.bpAmber, Color.bpAmberBright],
                                startPoint: .leading, endPoint: .trailing
                            ))
                            .frame(width: geo.size.width * 0.8)
                    }
                }
                .frame(height: 6)

                Text("4 / 5")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.75))
            }

            (
                Text("🎟 Premio: ")
                    .foregroundStyle(Color.white.opacity(0.75))
                + Text("Skip the Line gratis para los 5")
                    .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.bpAmberBright)
                + Text(" en Club Space")
                    .foregroundStyle(Color.white.opacity(0.75))
            )
            .font(.system(size: 12))
            .fixedSize(horizontal: false, vertical: true)
            .lineSpacing(2)
            .padding(.top, 2)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Section header

    private func sectionHeader(title: String, action: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            Text(action)
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(Color.bpAmberBright)
        }
    }

    // MARK: - Trivia card

    private var triviaCard: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Contra los que están adentro")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("5 preguntas · 90 s · premio del venue: trago de la casa")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button {
                actionLog("trivia_join")
            } label: {
                Text("Me apunto")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.bpAmber))
                    .overlay(Capsule().strokeBorder(Color.bpAmberBright, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Avatar unlocks

    private var unlocksRow: some View {
        HStack(alignment: .top, spacing: 10) {
            UnlockTile(
                color: Color.bpAmber,
                initial: "S",
                caption: "Gorra · nivel 4 ✓",
                captionColor: Color.bpGreen,
                locked: false,
                accessory: .cap
            ) { actionLog("unlock_cap") }

            UnlockTile(
                color: Color.bpAmber,
                initial: "S",
                caption: "Cadena · 1.500 BPX",
                captionColor: Color.white.opacity(0.65),
                locked: true,
                accessory: .chain
            ) { actionLog("unlock_chain") }

            UnlockTile(
                color: Color(red: 0.55, green: 0.4, blue: 0.95),
                initial: "S",
                caption: "Outfit morado · 3 venues nuevos",
                captionColor: Color.white.opacity(0.65),
                locked: true,
                accessory: .none
            ) { actionLog("unlock_outfit") }
        }
    }

    // MARK: - Helpers

    private func actionLog(_ name: String) {
        #if canImport(UIKit)
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.impactOccurred()
        #endif
        _ = name
    }
}

// MARK: - Background

@MainActor
private struct GamesMissionsBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.015, blue: 0.04).ignoresSafeArea()

            GeometryReader { proxy in
                Image("CityArtMiami")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width * 2.3,
                           height: proxy.size.width * 2.3)
                    .position(x: proxy.size.width * 0.5,
                              y: proxy.size.height * -0.05)
                    .opacity(0.5)
            }
            .ignoresSafeArea()

            RadialGradient(
                colors: [.clear, Color(red: 0.27, green: 0.09, blue: 0).opacity(0.42)],
                center: UnitPoint(x: 0.5, y: 0.3),
                startRadius: 180, endRadius: 720
            )
            .ignoresSafeArea()
            .blendMode(.multiply)

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.88), Color.black],
                startPoint: UnitPoint(x: 0.5, y: 0.3),
                endPoint: .bottom
            )
            .ignoresSafeArea()

            GrainTexture(opacity: 0.13)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Avatar primitive

@MainActor
private struct GamesAvatar: View {
    let color: Color
    let initial: String
    let size: CGFloat
    let ringAccent: Bool

    var body: some View {
        ZStack {
            // Shoulders / base
            Circle()
                .fill(color.opacity(0.22))
                .frame(width: size, height: size)

            // Face disc
            Circle()
                .fill(LinearGradient(
                    colors: [color.opacity(0.95), color.opacity(0.65)],
                    startPoint: .top, endPoint: .bottom
                ))
                .frame(width: size * 0.78, height: size * 0.78)

            // Hair cap arc (approximation)
            Circle()
                .trim(from: 0.55, to: 1.0)
                .fill(Color.black.opacity(0.55))
                .frame(width: size * 0.86, height: size * 0.86)
                .offset(y: -size * 0.04)

            Text(initial)
                .font(.system(size: size * 0.34, weight: .black, design: .rounded))
                .foregroundStyle(.black.opacity(0.75))

            if ringAccent {
                Circle()
                    .strokeBorder(Color.bpAmberBright, lineWidth: 2)
                    .frame(width: size + 4, height: size + 4)
                    .shadow(color: Color.bpAmber.opacity(0.5), radius: 6)
            }
        }
        .frame(width: size + (ringAccent ? 4 : 0),
               height: size + (ringAccent ? 4 : 0))
    }
}

// MARK: - Prediction pill

@MainActor
private struct PredictionPill: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(selected ? .black : Color.white.opacity(0.85))
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(selected
                                   ? Color.bpAmber
                                   : Color.white.opacity(0.06))
                )
                .overlay(
                    Capsule().strokeBorder(
                        selected ? Color.bpAmberBright : Color.white.opacity(0.14),
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Unlock tile

@MainActor
private struct UnlockTile: View {
    enum Accessory { case cap, chain, none }

    let color: Color
    let initial: String
    let caption: String
    let captionColor: Color
    let locked: Bool
    let accessory: Accessory
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    GamesAvatar(color: color, initial: initial, size: 58, ringAccent: false)
                        .opacity(locked ? 0.45 : 1)

                    switch accessory {
                    case .cap:
                        // Small amber "B" cap over the forehead
                        Image(systemName: "sportscourt.fill")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.clear)
                            .overlay(
                                Capsule()
                                    .fill(Color.bpAmber)
                                    .frame(width: 28, height: 10)
                                    .overlay(
                                        Text("B")
                                            .font(.system(size: 8, weight: .black, design: .rounded))
                                            .foregroundStyle(.black)
                                            .offset(x: -8)
                                    )
                                    .offset(y: -22)
                            )
                    case .chain:
                        Image(systemName: "link")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Color.bpAmber)
                            .offset(y: 18)
                    case .none:
                        EmptyView()
                    }

                    if locked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(.black)
                            .padding(5)
                            .background(Circle().fill(Color.bpAmber))
                            .offset(x: 20, y: 20)
                    }
                }

                Text(caption)
                    .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(captionColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    GamesMissionsV2View()
}
