import SwiftUI
import AVKit

/// Full-screen playback of one venue's night. Tap the right side to
/// advance, the left to go back, anywhere else it advances on its own.
///
/// The header answers the only two questions a story has to answer —
/// WHERE and HOW LONG AGO. It deliberately does not answer WHO: the server
/// never sends an author (supabase/venue_stories.sql), so there is no name
/// to render and no way for a viewer to reconstruct who was standing in a
/// bar at 1am. `posterSeq` groups frames shot by the same person, which is
/// what makes a run of four photos read as one person's night instead of
/// four unrelated tiles; it is a per-venue, per-night counter and means
/// nothing outside this screen.
struct StoryViewer: View {
    let venueName: String
    let stories: [VenueStory]
    var startIndex: Int = 0
    let onClose: () -> Void

    @ObservedObject private var l10n = L10n.shared
    @State private var index: Int = 0
    @State private var progress: Double = 0
    @State private var player: AVPlayer?
    @State private var isPaused = false

    /// A photo gets a beat long enough to read the room and short enough
    /// that eight of them are still one night, not a slideshow.
    private static let photoDuration: Double = 5
    /// Video is capped at 60s on upload (VenueMediaUploader); this is the
    /// ceiling for the progress bar when the player never reports an end.
    private static let videoDuration: Double = 15
    private static let tick: Double = 0.03

    private var current: VenueStory? {
        stories.indices.contains(index) ? stories[index] : nil
    }

    private var duration: Double {
        current?.mediaType == .video ? Self.videoDuration : Self.photoDuration
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let current {
                frame(current).ignoresSafeArea()
            }

            // Keeps the header legible over a bright frame (a phone flash
            // inside a club blows the top of the image out).
            LinearGradient(colors: [.black.opacity(0.75), .clear],
                           startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                progressBar
                header
                Spacer()
            }
            .padding(.horizontal, BPSpacing.md)
            .padding(.top, BPSpacing.sm)

            tapTargets
        }
        .statusBarHidden()
        .onAppear {
            index = min(max(startIndex, 0), max(stories.count - 1, 0))
            start()
        }
        .onDisappear { teardown() }
        .onReceive(Timer.publish(every: Self.tick, on: .main, in: .common).autoconnect()) { _ in
            guard !isPaused, !stories.isEmpty else { return }
            progress += Self.tick / duration
            if progress >= 1 { advance(by: 1) }
        }
    }

    // MARK: - Pieces

    private var progressBar: some View {
        HStack(spacing: 3) {
            ForEach(stories.indices, id: \.self) { i in
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.25))
                        Capsule().fill(Color.bpAmber)
                            .frame(width: geo.size.width * fill(for: i))
                    }
                }
                .frame(height: 2.5)
            }
        }
        .frame(height: 2.5)
        .padding(.bottom, BPSpacing.md)
        .accessibilityHidden(true)
    }

    private func fill(for i: Int) -> Double {
        if i < index { return 1 }
        if i > index { return 0 }
        return min(max(progress, 0), 1)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: BPSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(venueName)
                    .font(.bpScaled(15, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(current.map { StoryTime.ago($0.createdAt, l10n) } ?? "")
                        .font(.bpSmall())
                        .foregroundStyle(.white.opacity(0.7))
                    if current?.isMine == true {
                        Text(l10n.t("story.mine"))
                            .font(.bpTiny())
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.bpAmber, in: Capsule())
                    }
                }
            }
            Spacer()
            Button {
                BPHaptics.light()
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.bpScaled(15, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(Color.black.opacity(0.35), in: Circle())
            }
            .buttonStyle(.plain)
            .bpAccessibility(label: l10n.t("story.close"), isButton: true)
        }
        // One VoiceOver element for the whole header: the frame itself is
        // the content, and the label has to say what a sighted user sees —
        // where, when, and that nobody is named.
        .accessibilityElement(children: .contain)
    }

    /// Left third goes back, the rest advances — the proportions every
    /// story UI uses, so nobody has to learn them here.
    private var tapTargets: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                Color.clear.contentShape(Rectangle())
                    .frame(width: geo.size.width / 3)
                    .onTapGesture { advance(by: -1) }
                    .bpAccessibility(label: l10n.t("story.previous"), isButton: true)
                Color.clear.contentShape(Rectangle())
                    .onTapGesture { advance(by: 1) }
                    .bpAccessibility(label: l10n.t("story.next"), isButton: true)
            }
            // Press and hold to stop the clock — reading a caption-less
            // frame in a dark club takes longer than five seconds.
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPaused = true; player?.pause() }
                    .onEnded { _ in isPaused = false; player?.play() }
            )
        }
    }

    @ViewBuilder
    private func frame(_ story: VenueStory) -> some View {
        if story.mediaType == .video, let player {
            VideoPlayer(player: player)
                .onReceive(NotificationCenter.default.publisher(
                    for: AVPlayerItem.didPlayToEndTimeNotification)) { _ in
                    advance(by: 1)
                }
        } else if let url = URL(string: story.mediaUrl) {
            CachedImage(url: url, targetSize: CGSize(width: 1080, height: 1920), priority: .hot) { image in
                image.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                ProgressView().tint(Color.bpAmber)
            }
        }
    }

    // MARK: - Playback

    private func start() {
        progress = 0
        preparePlayer()
    }

    private func preparePlayer() {
        player?.pause()
        player = nil
        guard let current, current.mediaType == .video,
              let url = URL(string: current.mediaUrl) else { return }
        let new = AVPlayer(url: url)
        new.isMuted = false
        new.play()
        player = new
    }

    private func teardown() {
        player?.pause()
        player = nil
    }

    private func advance(by step: Int) {
        let next = index + step
        guard next >= 0 else {
            // Already at the first frame: restart it rather than closing,
            // so a mistimed tap never throws the user out of the night.
            progress = 0
            preparePlayer()
            return
        }
        guard next < stories.count else {
            BPHaptics.light()
            onClose()
            return
        }
        BPHaptics.selection()
        index = next
        progress = 0
        preparePlayer()
    }
}

/// "hace 12 min" without a `RelativeDateTimeFormatter` pinned to one
/// language. The app runs in three, and a story's age is the only number
/// on this screen.
enum StoryTime {
    @MainActor
    static func ago(_ date: Date, _ l10n: L10n) -> String {
        let seconds = max(Date().timeIntervalSince(date), 0)
        if seconds < 60 { return l10n.t("story.ago.now") }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return String(format: l10n.t("story.ago.minutes"), minutes) }
        return String(format: l10n.t("story.ago.hours"), minutes / 60)
    }
}
