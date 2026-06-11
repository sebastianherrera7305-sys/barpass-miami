import SwiftUI
import Combine
import Network

@MainActor
final class AppState: ObservableObject {
    @Published var showSplash = true
    @Published var isOffline  = false
    @Published var deepLinkURL: URL?

    private var minTimerDone = false
    private var webReadyDone = false
    private var cancellables = Set<AnyCancellable>()

    private let networkMonitor = NWPathMonitor()
    private let networkQueue   = DispatchQueue(label: "io.barpass.appstate.network", qos: .utility)

    init() {
        NotificationCenter.default.publisher(for: .deepLinkReceived)
            .compactMap { $0.object as? URL }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] url in self?.deepLinkURL = url }
            .store(in: &cancellables)

        networkMonitor.pathUpdateHandler = { [weak self] path in
            let offline = path.status != .satisfied
            Task { @MainActor in self?.isOffline = offline }
        }
        networkMonitor.start(queue: networkQueue)
    }

    func splashMinTimerFired() {
        minTimerDone = true
        maybeCompleteSplash()
    }

    func webDidSignalReady() {
        webReadyDone = true
        maybeCompleteSplash()
    }

    func splashComplete() {
        withAnimation(.easeOut(duration: 0.4)) { showSplash = false }
    }

    private func maybeCompleteSplash() {
        guard minTimerDone && webReadyDone else { return }
        withAnimation(.easeOut(duration: 0.4)) { showSplash = false }
    }
}
