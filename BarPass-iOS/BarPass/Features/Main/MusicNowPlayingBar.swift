import SwiftUI

/// Barra flotante "now playing" — aparece sobre el tab bar solo mientras
/// AppleMusicPlaybackService tiene algo sonando. Play/pausa, saltar y
/// parar del todo (el control que faltaba en el autoplay).
struct MusicNowPlayingBar: View {
    @ObservedObject private var observer = MusicNowPlayingObserver.shared
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        if let title = observer.title {
            HStack(spacing: 10) {
                CachedImage(url: observer.artworkURL, targetSize: CGSize(width: 36, height: 36)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 6).fill(Color.bpInk.opacity(0.1))
                        .overlay(Image(systemName: "music.note").font(.bpScaled(12)).foregroundStyle(Color.bpTextTertiary))
                }
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.bpScaled(12, weight: .semibold))
                        .foregroundStyle(Color.bpInk)
                        .lineLimit(1)
                    if let subtitle = observer.subtitle {
                        Text(subtitle)
                            .font(.bpScaled(10))
                            .foregroundStyle(Color.bpTextSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                Button { observer.togglePlayPause() } label: {
                    Image(systemName: observer.isPlaying ? "pause.fill" : "play.fill")
                        .font(.bpScaled(14))
                        .foregroundStyle(Color.bpInk)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .bpAccessibility(label: observer.isPlaying ? l10n.t("music.pause.a11y") : l10n.t("music.play.a11y"), isButton: true)

                Button { observer.skipToNext() } label: {
                    Image(systemName: "forward.fill")
                        .font(.bpScaled(13))
                        .foregroundStyle(Color.bpInk.opacity(0.7))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .bpAccessibility(label: l10n.t("music.next.a11y"), isButton: true)

                Button { observer.stop() } label: {
                    Image(systemName: "xmark")
                        .font(.bpScaled(12, weight: .semibold))
                        .foregroundStyle(Color.bpTextSecondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .bpAccessibility(label: l10n.t("music.stop.a11y"), hint: l10n.t("music.stop.hint"), isButton: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.bpAmber.opacity(0.2)))
            .padding(.horizontal, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityElement(children: .contain)
        }
    }
}
