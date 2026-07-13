import SwiftUI

/// "Your Hype This Week 🔥" — la puerta de entrada a Music Intelligence.
/// Estados honestos: bienvenida → conectando → hype real → (denied/notEntitled
/// explicados). Sin música conectada NO muestra datos fake jamás.
struct HypeWeekCard: View {
    @ObservedObject private var music = MusicProfileStore.shared

    var body: some View {
        Group {
            switch music.state {
            case .notConnected:      welcomeCard
            case .connecting:        loadingCard
            case .connected:         if let p = music.passport { hypeCard(p) }
            case .denied:            infoCard(icon: "gear", text: "Permiso de Apple Music desactivado. Activalo en Ajustes ▸ BarPass para ver tu Hype semanal.")
            case .notEntitled:       infoCard(icon: "hourglass", text: "Music Intelligence se activa cuando BarPass complete su registro de MusicKit con Apple. Muy pronto.")
            case .noData:            infoCard(icon: "music.note", text: "No encontramos escucha reciente en Apple Music. Escuchá algo esta semana y volvé 😉")
            case .error:             infoCard(icon: "wifi.slash", text: "No pudimos leer tu música. Reintentá más tarde.")
            }
        }
    }

    // MARK: - Bienvenida (primera vez)

    private var welcomeCard: some View {
        Button {
            BPHaptics.medium()
            Task { await music.connect() }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.bpAmber.opacity(0.15)).frame(width: 46, height: 46)
                    Text("🎵").font(.bpScaled(22))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Conectá tu música")
                        .font(.bpScaled(15, weight: .bold)).foregroundStyle(Color.bpInk)
                    Text("Descubrí a dónde salir según lo que escuchás. Tu música nunca sale de tu teléfono.")
                        .font(.bpScaled(11)).foregroundStyle(Color.bpTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.bpScaled(13, weight: .semibold)).foregroundStyle(Color.bpAmber)
            }
            .padding(14)
            .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.lg))
            .overlay(RoundedRectangle(cornerRadius: BPRadius.lg).strokeBorder(Color.bpAmber.opacity(0.25)))
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: "Conectar tu música", hint: "Conectar Apple Music para recomendaciones personalizadas", isButton: true)
    }

    private var loadingCard: some View {
        HStack(spacing: 12) {
            ProgressView().tint(Color.bpAmber)
            Text("Leyendo tu semana musical…")
                .font(.bpScaled(13)).foregroundStyle(Color.bpTextSecondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 18)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.lg))
    }

    // MARK: - Hype real

    private func hypeCard(_ p: MusicPassport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Your Hype This Week 🔥")
                    .font(.bpScaled(15, weight: .black)).foregroundStyle(Color.bpInk)
                Spacer()
                Text(p.nightPersonality)
                    .font(.bpScaled(10, weight: .bold)).foregroundStyle(Color.bpAmber)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.bpAmber.opacity(0.12), in: Capsule())
            }

            Text("Tu semana fue \(p.energy)% High Energy")
                .font(.bpScaled(13, weight: .semibold)).foregroundStyle(Color.bpInk.opacity(0.85))

            // Barra de energía
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.bpInk.opacity(0.08)).frame(height: 5)
                    Capsule()
                        .fill(LinearGradient(colors: [Color.bpAmber, Color.bpAmberBright],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(p.energy) / 100, height: 5)
                }
            }
            .frame(height: 5)

            if !p.topGenres.isEmpty {
                Text(p.topGenres.prefix(3).map(\.genre).joined(separator: " + "))
                    .font(.bpScaled(11, weight: .semibold)).foregroundStyle(Color.bpTextSecondary)
            }
            if !p.topArtists.isEmpty {
                Text("Definiendo tu semana: \(p.topArtists.prefix(3).joined(separator: ", "))")
                    .font(.bpScaled(11)).foregroundStyle(Color.bpTextSecondary)
                    .lineLimit(1)
            }
            if !p.newDiscoveries.isEmpty {
                Text("✨ \(p.newDiscoveries.count) artista\(p.newDiscoveries.count == 1 ? "" : "s") nuevo\(p.newDiscoveries.count == 1 ? "" : "s") esta semana")
                    .font(.bpScaled(10, weight: .semibold)).foregroundStyle(Color.bpGreen)
            }
        }
        .padding(14)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.lg).strokeBorder(Color.bpAmber.opacity(0.2)))
        .accessibilityElement(children: .ignore)
        .bpAccessibility(label: "Tu hype semanal: \(p.energy) por ciento high energy, personalidad \(p.nightPersonality)")
    }

    private func infoCard(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.bpScaled(15)).foregroundStyle(Color.bpAmber)
            Text(text).font(.bpScaled(11)).foregroundStyle(Color.bpTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color.bpCardBackground.opacity(0.7), in: RoundedRectangle(cornerRadius: BPRadius.md))
    }
}
