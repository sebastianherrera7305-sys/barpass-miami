import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var showSplash = true
    @Published var isOffline  = false
    @Published var deepLinkURL: URL?

    private var cancellables = Set<AnyCancellable>()

    init() {
        NotificationCenter.default.publisher(for: .deepLinkReceived)
            .compactMap { $0.object as? URL }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] url in self?.deepLinkURL = url }
            .store(in: &cancellables)
    }

    func splashComplete() {
        withAnimation(.easeOut(duration: 0.4)) { showSplash = false }
    }
}
