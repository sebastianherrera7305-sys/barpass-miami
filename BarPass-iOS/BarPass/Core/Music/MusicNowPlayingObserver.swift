import Foundation
import MusicKit
import Combine

/// Puente entre ApplicationMusicPlayer (MusicKit) y SwiftUI — sin esto, el
/// autoplay de AppleMusicPlaybackService arranca música que el usuario no
/// puede pausar, saltar ni parar desde la app.
@MainActor
final class MusicNowPlayingObserver: ObservableObject {
    static let shared = MusicNowPlayingObserver()

    @Published private(set) var isPlaying = false
    @Published private(set) var title: String?
    @Published private(set) var subtitle: String?
    @Published private(set) var artworkURL: URL?

    private let player = ApplicationMusicPlayer.shared
    private var cancellables = Set<AnyCancellable>()

    private init() {
        player.state.objectWillChange
            .sink { [weak self] in self?.refresh() }
            .store(in: &cancellables)
        player.queue.objectWillChange
            .sink { [weak self] in self?.refresh() }
            .store(in: &cancellables)
    }

    private func refresh() {
        isPlaying = player.state.playbackStatus == .playing
        if let entry = player.queue.currentEntry {
            title = entry.title
            subtitle = entry.subtitle
            artworkURL = entry.artwork?.url(width: 100, height: 100)
        } else {
            title = nil
            subtitle = nil
            artworkURL = nil
        }
    }

    func togglePlayPause() {
        if player.state.playbackStatus == .playing {
            player.pause()
        } else {
            Task { try? await ApplicationMusicPlayer.shared.play() }
        }
    }

    func skipToNext() {
        Task { try? await ApplicationMusicPlayer.shared.skipToNextEntry() }
    }

    func stop() {
        player.stop()
        title = nil
        subtitle = nil
        artworkURL = nil
        isPlaying = false
    }
}
