import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var showSplash = true
    @Published var isOffline  = false
    @Published var deepLinkURL: URL?

    private var minTimerDone = false
    private var webReadyDone = false
    private var cancellables = Set<AnyCancellable>()

    init() {
        NotificationCenter.default.publisher(for: .deepLinkReceived)
            .compactMap { $0.object as? URL }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] url in self?.deepLinkURL = url }
            .store(in: &cancellables)
    }

    // Called by SplashView after minimum display time
    func splashMinTimerFired() {
        minTimerDone = true
        maybeCompleteSplash()
    }

    // Called by NativeBridge when the JS web app fires signalReady()
    func webDidSignalReady() {
        webReadyDone = true
        maybeCompleteSplash()
    }

    // Safety-net: hides splash unconditionally (if web never fires ready)
    func splashComplete() {
        withAnimation(.easeOut(duration: 0.4)) { showSplash = false }
    }

    private func maybeCompleteSplash() {
        guard minTimerDone && webReadyDone else { return }
        withAnimation(.easeOut(duration: 0.4)) { showSplash = false }
    }
}
