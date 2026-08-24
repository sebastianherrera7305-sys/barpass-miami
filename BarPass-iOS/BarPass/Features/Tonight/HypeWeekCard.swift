import SwiftUI

/// "Your Hype This Week 🔥" — la puerta de entrada a Music Intelligence.
/// Estados honestos: bienvenida → conectando → hype real → (denied/notEntitled
/// explicados). Sin música conectada NO muestra datos fake jamás.
struct HypeWeekCard: View {
    @ObservedObject private var music = MusicProfileStore.shared
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        Group {
            switch music.state {
            case .notConnected:      welcomeCard
            case .connecting:        loadingCard
            case .connected:         if let p = music.passport { hypeCard(p) }
            case .denied:            infoCard(icon: "gear", text: l10n.t("hype.denied"))
            case .notEntitled:       notEntitledCard
            case .noData:            infoCard(icon: "music.note", text: l10n.t("hype.noData"))
            case .error:             infoCard(icon: "wifi.slash", text: l10n.t("hype.error"))
            }
        }
    }

    // MARK: - Bienvenida (primera vez)

    private var welcomeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.bpAmber.opacity(0.15)).frame(width: 46, height: 46)
                    Text("🎵").font(.bpScaled(22))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(l10n.t("hype.welcome.title"))
                        .font(.bpScaled(15, weight: .bold)).foregroundStyle(Color.bpInk)
                    Text(l10n.t("hype.welcome.subtitle"))
                        .font(.bpScaled(11)).foregroundStyle(Color.bpTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                providerButton(" Apple Music", kind: .appleMusic)
                providerButton("Spotify", kind: .spotify)
            }
        }
        .padding(14)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.lg).strokeBorder(Color.bpAmber.opacity(0.25)))
    }

    private func providerButton(_ label: String, kind: MusicSourceKind) -> some View {
        Button {
            BPHaptics.medium()
            Task { await music.connect(kind) }
        } label: {
            Text(label)
                .font(.bpScaled(13, weight: .bold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(kind == .spotify ? Color(red: 0.11, green: 0.84, blue: 0.38) : Color.bpAmber,
                            in: Capsule())
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: String(format: l10n.t("hype.connect.label"), kind.label), hint: String(format: l10n.t("hype.connect.hint"), kind.label), isButton: true)
    }

    private var loadingCard: some View {
        HStack(spacing: 12) {
            Image("BarPassMascot")
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
            Text(l10n.t("hype.loading"))
                .font(.bpScaled(13)).foregroundStyle(Color.bpTextSecondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 18)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.lg))
    }

    // MARK: - Hype real

    private func hypeCard(_ p: MusicPassport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(l10n.t("hype.title"))
                    .font(.bpScaled(15, weight: .black)).foregroundStyle(Color.bpInk)
                Spacer()
                Text(p.nightPersonality)
                    .font(.bpScaled(10, weight: .bold)).foregroundStyle(Color.bpAmber)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.bpAmber.opacity(0.12), in: Capsule())
            }

            Text(String(format: l10n.t("hype.energy"), p.energy))
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
                artistRow(p.topArtists)
            }
            if !p.newDiscoveries.isEmpty {
                Text(String(format: p.newDiscoveries.count == 1 ? l10n.t("hype.newDiscoveries.singular") : l10n.t("hype.newDiscoveries.plural"), p.newDiscoveries.count))
                    .font(.bpScaled(10, weight: .semibold)).foregroundStyle(Color.bpGreen)
            }
        }
        .padding(14)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.lg).strokeBorder(Color.bpAmber.opacity(0.2)))
        .accessibilityElement(children: .ignore)
        .bpAccessibility(label: String(format: l10n.t("hype.a11y.label"), p.energy, p.nightPersonality))
    }

    /// Fila de artistas con foto real — antes esto era solo texto plano.
    private func artistRow(_ artists: [ArtistPlay]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(l10n.t("hype.defining"))
                .font(.bpScaled(9, weight: .bold)).foregroundStyle(Color.bpTextTertiary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(artists.prefix(8), id: \.name) { artist in
                        VStack(spacing: 4) {
                            CachedImage(url: artist.imageURL, targetSize: CGSize(width: 56, height: 56)) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Circle().fill(Color.bpInk.opacity(0.08))
                                    .overlay(Text("🎤").font(.bpScaled(16)))
                            }
                            .frame(width: 52, height: 52)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(Color.bpAmber.opacity(0.25)))

                            Text(artist.name)
                                .font(.bpScaled(9, weight: .semibold))
                                .foregroundStyle(Color.bpTextSecondary)
                                .lineLimit(1)
                                .frame(width: 56)
                        }
                    }
                }
            }
        }
        .bpAccessibility(label: String(format: l10n.t("hype.artists.a11y"), artists.prefix(5).map(\.name).joined(separator: ", ")))
    }

    /// Apple Music bloqueado (falta registro MusicKit) → Spotify como alternativa real.
    private var notEntitledCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "hourglass").font(.bpScaled(15)).foregroundStyle(Color.bpAmber)
                Text(l10n.t("hype.notEntitled"))
                    .font(.bpScaled(11)).foregroundStyle(Color.bpTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            providerButton(l10n.t("hype.connectSpotify"), kind: .spotify)
        }
        .padding(12)
        .background(Color.bpCardBackground.opacity(0.7), in: RoundedRectangle(cornerRadius: BPRadius.md))
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
