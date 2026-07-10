import SwiftUI
import AVKit

// Drop your Higgsfield clips into BarPass/Resources/Onboarding/
// and name them: scene1.mp4, scene2.mp4 ... scene6.mp4
// They play in sequence with crossfade, then show NativeAuthView.

@MainActor
struct OnboardingVideoView: View {
    @EnvironmentObject private var appState: AppState
    @State private var currentScene  = 0
    @State private var opacity:  Double = 0
    @State private var textOpacity: Double = 0
    @State private var player: AVPlayer?
    @State private var isFinished = false

    private let scenes: [SceneInfo] = [
        SceneInfo(file: "scene1", caption: nil),
        SceneInfo(file: "scene2", caption: "Desde el juego hasta la fiesta"),
        SceneInfo(file: "scene3", caption: "Festivales. Cultura. Energía."),
        SceneInfo(file: "scene4", caption: nil),
        SceneInfo(file: "scene5", caption: "Los mejores clubs. Tu acceso."),
        SceneInfo(file: "scene6", caption: "Un toque. Adentro."),
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

            // Gradient overlay bottom
            LinearGradient(
                colors: [.clear, .black.opacity(0.7)],
                startPoint: .center,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack {
                Spacer()

                // Caption
                if let caption = scenes[safe: currentScene]?.caption {
                    Text(caption)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.6), radius: 8)
                        .opacity(textOpacity)
                        .animation(.easeInOut(duration: 0.5), value: textOpacity)
                        .padding(.horizontal, 32)
                }

                // Scene dots
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

            // Skip button
            VStack {
                HStack {
                    Spacer()
                    Button("Saltar") { finish() }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .padding(.trailing, 24)
                        .padding(.top, 56)
                }
                Spacer()
            }
        }
        .onTapGesture { advanceScene() }
        .onAppear {
            // If no video clips are bundled yet, skip straight to auth —
            // otherwise the user stares at ~30s of black screens.
            let hasAnyVideo = scenes.contains {
                Bundle.main.url(forResource: $0.file, withExtension: "mp4", subdirectory: "Onboarding") != nil
            }
            if hasAnyVideo {
                startScene(0)
            } else {
                finish()
            }
        }
        .onDisappear { player?.pause() }
    }

    // MARK: - Scene control

    private func startScene(_ index: Int) {
        guard index < scenes.count else { finish(); return }
        currentScene = index
        opacity = 0
        textOpacity = 0

        let scene = scenes[index]

        // Try bundle resource, fall back to placeholder
        if let url = Bundle.main.url(forResource: scene.file, withExtension: "mp4",
                                      subdirectory: "Onboarding") {
            let newPlayer = AVPlayer(url: url)
            newPlayer.isMuted = true
            self.player = newPlayer

            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: newPlayer.currentItem,
                queue: .main
            ) { _ in Task { @MainActor in advanceScene() } }

            newPlayer.play()
            withAnimation { opacity = 1 }

            // Show caption after 0.5s
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation { textOpacity = 1 }
            }
            // Auto-advance after duration (fallback 4s if video shorter)
            let duration = scene.duration
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                if self.currentScene == index { advanceScene() }
            }
        } else {
            // No video file yet — show placeholder and auto-advance
            withAnimation { opacity = 1; textOpacity = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + scenes[index].duration) {
                if self.currentScene == index { advanceScene() }
            }
        }
    }

    private func advanceScene() {
        guard !isFinished else { return }
        let next = currentScene + 1
        if next < scenes.count {
            withAnimation(.easeInOut(duration: 0.4)) { opacity = 0; textOpacity = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                player?.pause()
                startScene(next)
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

// MARK: - Supporting types

private struct SceneInfo {
    let file:     String
    let caption:  String?
    var duration: Double = 5.0
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - AVPlayer UIViewRepresentable

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
