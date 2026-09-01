import SwiftUI
import AVKit
import Combine

@MainActor
struct OnboardingVideoView: View {
    @ObservedObject private var l10n = L10n.shared
    @EnvironmentObject private var appState: AppState
    @State private var currentScene  = 0
    @State private var opacity:  Double = 0
    @State private var textOpacity: Double = 0
    @State private var player: AVPlayer?
    @State private var isFinished = false
    @State private var cancellables = Set<AnyCancellable>()

    // Las captions se guardan como CLAVE, no como texto ya resuelto: `scenes`
    // es un `let` que se evalúa una sola vez, así que un `l10n.t(...)` aquí
    // congelaría el idioma del primer render y el cambio en caliente dejaría
    // de funcionar solo en esta pantalla. Se resuelven en el `body`.
    private let scenes: [SceneInfo] = [
        SceneInfo(file: "scene1", captionKey: nil),
        SceneInfo(file: "scene2", captionKey: "onboarding.caption.2"),
        SceneInfo(file: "scene3", captionKey: "onboarding.caption.3"),
        SceneInfo(file: "scene4", captionKey: nil),
        SceneInfo(file: "scene5", captionKey: "onboarding.caption.5"),
        SceneInfo(file: "scene6", captionKey: "onboarding.caption.6"),
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayerLayer(player: player)
                    .ignoresSafeArea()
                    .opacity(opacity)
                    .animation(.easeInOut(duration: 0.6), value: opacity)
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.7)],
                startPoint: .center,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack {
                Spacer()

                if let captionKey = scenes[safe: currentScene]?.captionKey {
                    Text(l10n.t(captionKey))
                        .font(.bpScaled(22, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.6), radius: 8)
                        .opacity(textOpacity)
                        .animation(.easeInOut(duration: 0.5), value: textOpacity)
                        .padding(.horizontal, 32)
                }

                HStack(spacing: 6) {
                    ForEach(0..<scenes.count, id: \.self) { i in
                        Capsule()
                            .fill(i == currentScene ? Color.white : Color.white.opacity(0.3))
                            .frame(width: i == currentScene ? 20 : 6, height: 6)
                            .animation(.spring(response: 0.3), value: currentScene)
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 60)
            }
            .accessibilityElement(children: .ignore)
            .bpAccessibility(label: String(format: l10n.t("onboarding.scene.a11y"), currentScene + 1, scenes.count), hint: l10n.t("onboarding.scene.hint"))

            VStack {
                HStack {
                    Spacer()
                    Button(l10n.t("onboarding.skip")) { finish() }
                        .font(.bpScaled(14, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .padding(.trailing, 24)
                        .padding(.top, 56)
                        .bpAccessibility(label: l10n.t("onboarding.skip"), hint: l10n.t("onboarding.skip.hint"), isButton: true)
                }
                Spacer()
            }
        }
        .bpAccessibility(label: l10n.t("onboarding.video.a11y"), hint: l10n.t("onboarding.video.hint"), isButton: true)
        .onTapGesture { advanceScene() }
        .onAppear {
            let hasAnyVideo = scenes.contains {
                Bundle.main.url(forResource: $0.file, withExtension: "mp4", subdirectory: "Onboarding") != nil
            }
            if hasAnyVideo {
                startScene(0)
            } else {
                finish()
            }
        }
        .onDisappear {
            player?.pause()
            cancellables.removeAll()
        }
    }

    private func startScene(_ index: Int) {
        guard index < scenes.count else { finish(); return }
        currentScene = index
        opacity = 0
        textOpacity = 0

        let scene = scenes[index]

        if let url = Bundle.main.url(forResource: scene.file, withExtension: "mp4",
                                      subdirectory: "Onboarding") {
            let newPlayer = AVPlayer(url: url)
            newPlayer.isMuted = true
            self.player = newPlayer

            NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: newPlayer.currentItem)
                .sink { _ in Task { @MainActor in self.advanceScene() } }
                .store(in: &cancellables)

            newPlayer.play()
            withAnimation { opacity = 1 }

            Task {
                try? await Task.sleep(nanoseconds: UInt64(0.5 * 1_000_000_000))
                await MainActor.run { withAnimation { self.textOpacity = 1 } }
            }

            Task {
                try? await Task.sleep(nanoseconds: UInt64(scene.duration * 1_000_000_000))
                await MainActor.run {
                    if self.currentScene == index { self.advanceScene() }
                }
            }
        } else {
            withAnimation { opacity = 1; textOpacity = 1 }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(scenes[index].duration * 1_000_000_000))
                await MainActor.run {
                    if self.currentScene == index { self.advanceScene() }
                }
            }
        }
    }

    private func advanceScene() {
        guard !isFinished else { return }
        let next = currentScene + 1
        if next < scenes.count {
            withAnimation(.easeInOut(duration: 0.4)) { opacity = 0; textOpacity = 0 }
            Task {
                try? await Task.sleep(nanoseconds: 400_000_000)
                await MainActor.run {
                    self.player?.pause()
                    self.startScene(next)
                }
            }
        } else {
            finish()
        }
    }

    private func finish() {
        guard !isFinished else { return }
        isFinished = true
        player?.pause()
        withAnimation(.easeOut(duration: 0.4)) {
            appState.showOnboarding = false
        }
    }
}

private struct SceneInfo {
    let file:       String
    /// Clave de l10n, no el texto ya traducido — ver nota en `scenes`.
    let captionKey: String?
    var duration:   Double = 5.0
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private struct VideoPlayerLayer: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.player = player
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        view.player = player
    }
}

private final class PlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var player: AVPlayer? {
        get { (layer as? AVPlayerLayer)?.player }
        set {
            (layer as? AVPlayerLayer)?.player = newValue
            (layer as? AVPlayerLayer)?.videoGravity = .resizeAspectFill
        }
    }
}

#Preview {
    OnboardingVideoView()
        .environmentObject(AppState())
}
