import SwiftUI

// GamesMissionsV2View — Pantalla "Juegos y misiones" del artifact v17.1
// (grupo "Cuenta y seguridad", líneas 2587-2745 del mockup).
//
// Esta primera versión se publicaba con DATOS FABRICADOS: podio con 3
// personas (Mía 2.310, Tú 1.240, Jules 980), "predicción abierta" de hora
// pico en Club Space, misión de grupo 4/5, trivia "Contra los que están
// adentro", y 3 tiles de desbloqueo de avatar. Nada de eso era real:
// no hay backend de leaderboard, ni predicciones, ni avatares desbloqueables,
// y la "misión de grupo" no se parece a lo que el `MissionEngine` genera
// (misiones individuales diarias). Mostrar "DJ_Luna 2.310" al lado del
// usuario inventaba una red social — el memory del proyecto es explícito:
// nunca fabricar datos sociales ni rankings.
//
// Qué quedó real (2026-10-10):
//   · Header eyebrow → nivel y XP acumulados del PointsEngine.
//   · "Tu progreso" (una sola tarjeta tipo podio centrada) → avatar + nombre
//     + totalXP + check-ins + progreso al próximo nivel.
//   · "Misión de hoy" → primera misión no completada del MissionEngine, con
//     progreso real y XP real. Si todas están hechas, estado vacío honesto.
//   · "Más misiones" → scroll horizontal con el resto, mismo estilo que la
//     V1 (`GamificationView.missionCard`).
//
// Qué se ocultó por falta de backend:
//   · Podio Mía/Jules (no hay tabla de ranking de amigos).
//   · Tarjeta de predicción (no hay backend de prediction markets).
//   · Trivia "contra los que están adentro" (concepto distinto al de
//     `TriviaEngine`, que es una pregunta diaria individual).
//   · "Desbloqueos del avatar" (gorra/cadena/outfit no existen).
//
// Si cualquiera de esos features llega al backend, se re-habilita la
// sección con los componentes visuales que quedaron en el archivo
// (GamesAvatar sigue acá y acepta cualquier avatar real).
//
// Estilo: idéntico al mockup — fondo Miami eye + warm vignette + grain,
// tipografía black rounded / serif italic / mono tracked, cards
// Color.white.opacity(0.04) con stroke 0.08, acento amber.

@MainActor
struct GamesMissionsV2View: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var engine = PointsEngine.shared
    @ObservedObject private var missionEngine = MissionEngine.shared
    @ObservedObject private var l10n = L10n.shared

    @State private var displayName: String?

    var body: some View {
        ZStack {
            GamesMissionsBackground()

            VStack(spacing: 0) {
                // iOS pinta el status bar real; conservamos el aire superior
                // que ocupaba el chrome del mockup para que nada salte.
                Color.clear.frame(height: 14)
                navBar

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                            .padding(.horizontal, 22)
                            .padding(.top, 10)

                        progressCard
                            .padding(.horizontal, 20)

                        // "Misión de hoy" — primera misión abierta, o estado
                        // vacío si ya terminó todas.
                        if let active = firstOpenMission {
                            liveMissionCard(active)
                                .padding(.horizontal, 20)
                        } else if !missionEngine.missions.isEmpty {
                            allDoneCard
                                .padding(.horizontal, 20)
                        }

                        if remainingMissions.count > 0 {
                            sectionHeader(
                                title: "Más misiones",
                                action: "\(completedCount) / \(missionEngine.missions.count)"
                            )
                            .padding(.horizontal, 22)
                            .padding(.top, 4)

                            missionsStrip
                                .padding(.bottom, 24)
                        } else {
                            Spacer().frame(height: 24)
                        }
                    }
                    .padding(.top, 14)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            // Hace falta pedirle al MissionEngine que cargue (o rote) por si
            // el usuario abre la screen antes de haber tocado otra pantalla
            // que las toque (ProfileView las toca al aparecer).
            missionEngine.loadMissions()
            displayName = (try? await RepositoryDependencies.displayName.getDisplayName()) ?? nil
        }
    }

    // MARK: - Derivaciones de datos reales

    private var firstOpenMission: Mission? {
        missionEngine.missions.first(where: { !$0.isCompleted })
    }

    /// Misiones que NO son la "activa" renderizada arriba, para el strip
    /// horizontal. Si no hay activa, mostramos todas (completadas incluidas).
    private var remainingMissions: [Mission] {
        guard let active = firstOpenMission else { return missionEngine.missions }
        return missionEngine.missions.filter { $0.id != active.id }
    }

    private var completedCount: Int {
        missionEngine.missions.filter { $0.isCompleted }.count
    }

    private var userInitial: String {
        if let name = displayName?.trimmingCharacters(in: .whitespaces),
           let first = name.first {
            return String(first).uppercased()
        }
        return "?"
    }

    private var userName: String {
        if let name = displayName?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
            return name
        }
        return "Tú"
    }

    private var formattedXP: String { Self.decimal.string(for: engine.totalXP) ?? "\(engine.totalXP)" }

    private var xpToNextLevel: Int? {
        guard let next = engine.xpForNextLevel else { return nil }
        return max(0, next - engine.totalXP)
    }

    private static let decimal: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "es_ES")
        return f
    }()

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
                Text(eyebrowText)
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .tracking(1.8)
                    .foregroundStyle(Color.bpAmberBright)
                    .lineLimit(1)
            }

            (
                Text("Tu ")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                + Text("progreso")
                    .font(.system(size: 24, design: .serif).italic())
                    .foregroundStyle(Color.bpAmberBright)
            )
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var eyebrowText: String {
        let levelUpper = engine.levelName.uppercased()
        // `xpToNextLevel` ya es el RESTANTE (piso del próximo nivel − totalXP),
        // que es lo que "XP PARA SUBIR" promete. Nil = nivel máximo.
        if let remaining = xpToNextLevel, remaining > 0 {
            let remainingText = Self.decimal.string(for: remaining) ?? "\(remaining)"
            return "NIVEL \(levelUpper) · \(remainingText) XP PARA SUBIR"
        }
        return "NIVEL \(levelUpper) · MÁXIMO"
    }

    // MARK: - Progreso del usuario (un solo slot, centrado)
    //
    // Reemplazó el podio con 3 personas que inventaba nombres y puntajes
    // de amigos que no existen en ningún backend. Mantenemos la forma de
    // tarjeta de vidrio con stroke suave para que la screen no quede
    // esquelética — pero sólo con datos reales del `PointsEngine`.

    private var progressCard: some View {
        VStack(spacing: 10) {
            GamesAvatar(color: Color.bpAmber, initial: userInitial, size: 76, ringAccent: true)

            Text(userName)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.bpAmberBright)
                .lineLimit(1)

            Text(formattedXP + " XP")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            // Progreso al próximo nivel — barra honesta (0 si está en el tope).
            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                        Capsule()
                            .fill(LinearGradient(
                                colors: [Color.bpAmber, Color.bpAmberBright],
                                startPoint: .leading, endPoint: .trailing
                            ))
                            .frame(width: geo.size.width * CGFloat(min(max(engine.progress, 0), 1)))
                    }
                }
                .frame(height: 6)

                HStack(spacing: 10) {
                    statChip(label: "Check-ins", value: "\(engine.checkinCount)")
                    statChip(label: "Nivel", value: engine.levelName)
                    if let nextName = engine.nextLevelName,
                       let remaining = xpToNextLevel, remaining > 0 {
                        statChip(
                            label: "Para " + nextName,
                            value: "+\(Self.decimal.string(for: remaining) ?? "\(remaining)") XP",
                            tint: Color.bpGreen
                        )
                    }
                }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .bpAccessibility(label: progressA11yLabel, hint: progressA11yHint)
    }

    /// Label de VoiceOver de la tarjeta de progreso: sólo los mismos datos
    /// reales que ya se pintan (nombre, XP, nivel, check-ins).
    private var progressA11yLabel: String {
        var parts = [userName, formattedXP + " XP", "Nivel " + engine.levelName]
        parts.append("\(engine.checkinCount) check-ins")
        return parts.joined(separator: ", ")
    }

    private var progressA11yHint: String {
        if let nextName = engine.nextLevelName,
           let remaining = xpToNextLevel, remaining > 0 {
            return "+\(Self.decimal.string(for: remaining) ?? "\(remaining)") XP para " + nextName
        }
        return "Nivel máximo alcanzado"
    }

    @ViewBuilder
    private func statChip(label: String, value: String, tint: Color = Color.white.opacity(0.75)) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
            Text(label.uppercased())
                .font(.system(size: 8.5, weight: .heavy, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(Color.white.opacity(0.45))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Misión activa (reemplaza "Misión de grupo")

    private func liveMissionCard(_ m: Mission) -> some View {
        let title = l10n.t(m.title)
        let desc  = l10n.t(m.description)
        let progress = min(Double(m.progress) / Double(max(m.requirement, 1)), 1)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Misión de hoy")
                    .font(.system(size: 14.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Text(m.isCompleted ? "lista" : "en juego")
                    .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(m.isCompleted ? Color.bpGreen : Color.bpAmberBright)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill((m.isCompleted ? Color.bpGreen : Color.bpAmberBright).opacity(0.14)))
                    .overlay(Capsule().strokeBorder((m.isCompleted ? Color.bpGreen : Color.bpAmberBright).opacity(0.4), lineWidth: 1))
            }

            Text(title)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text(desc)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)

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
                            .frame(width: geo.size.width * CGFloat(progress))
                    }
                }
                .frame(height: 6)

                Text("\(min(m.progress, m.requirement)) / \(m.requirement)")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.75))
            }

            (
                Text("🎟 Premio: ")
                    .foregroundStyle(Color.white.opacity(0.75))
                + Text("+\(m.xpReward) XP")
                    .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.bpAmberBright)
                + Text(" al completarla")
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
        .accessibilityElement(children: .ignore)
        .bpAccessibility(
            label: String(format: l10n.t("games.mission.a11y"), title, m.progress, m.requirement),
            hint: desc
        )
    }

    /// Estado vacío cuando todas las misiones del día ya se completaron.
    private var allDoneCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Misión de hoy")
                    .font(.system(size: 14.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Text("todo listo")
                    .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(Color.bpGreen)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(Color.bpGreen.opacity(0.14)))
                    .overlay(Capsule().strokeBorder(Color.bpGreen.opacity(0.4), lineWidth: 1))
            }
            Text("Terminaste las misiones de hoy. Mañana rotan nuevas.")
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
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

    // MARK: - Strip horizontal de misiones

    private var missionsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(remainingMissions) { mission in
                    missionTile(mission)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func missionTile(_ m: Mission) -> some View {
        let title = l10n.t(m.title)
        let desc  = l10n.t(m.description)
        let progress = min(Double(m.progress) / Double(max(m.requirement, 1)), 1)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: m.isCompleted ? "checkmark.circle.fill" : m.icon)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(m.isCompleted ? Color.bpGreen : Color.bpAmber)
                Spacer()
                Text("+\(m.xpReward) XP")
                    .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Color.bpAmberBright)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Capsule().fill(Color.bpAmber.opacity(0.12)))
            }

            Text(title)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(desc)
                .font(.system(size: 10.5))
                .foregroundStyle(Color.white.opacity(0.6))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(m.isCompleted ? Color.bpGreen : Color.bpAmber)
                        .frame(width: geo.size.width * CGFloat(progress))
                }
            }
            .frame(height: 5)

            Text("\(min(m.progress, m.requirement)) / \(m.requirement)")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundStyle(m.isCompleted ? Color.bpGreen : Color.white.opacity(0.65))
        }
        .padding(12)
        .frame(width: 170)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(m.isCompleted ? Color.bpGreen.opacity(0.3) : Color.white.opacity(0.08), lineWidth: 1)
        )
        .opacity(m.isCompleted ? 0.75 : 1)
        .accessibilityElement(children: .ignore)
        .bpAccessibility(
            label: String(format: l10n.t("games.mission.a11y"), title, m.progress, m.requirement),
            hint: desc
        )
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

#Preview {
    GamesMissionsV2View()
        .preferredColorScheme(.dark)
}
