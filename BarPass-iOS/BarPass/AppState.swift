import SwiftUI
import Combine
import Network

struct OrderConfirmation: Equatable {
    let venue:  String
    let items:  String
    let total:  Double
    let method: String
}

@MainActor
final class AppState: ObservableObject {
    @Published var showSplash             = true
    @Published var showOnboarding         = true
    @Published var showActionBar          = false
    @Published var showNativeAuth         = true
    @Published var isOffline              = false
    @Published var deepLinkURL:            URL?
    @Published var showCart               = false
    @Published var walletBalance:          Double = 0
    @Published var lastOrderConfirmation:  OrderConfirmation?
    @Published var showPriorityEntry       = false
    @Published var priorityVenueId:        String = ""
    @Published var priorityVenueName:      String = ""
    @Published var authError:              String = ""

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
        scheduleActionBar(delay: 0.6)
        withAnimation(.easeInOut(duration: 0.5)) { showNativeAuth = false }
    }

    func splashComplete() {
        withAnimation(.easeOut(duration: 0.4)) { showSplash = false }
        // Safety timer dismisses splash only — action bar waits for web signal
    }

    private func scheduleActionBar(delay: Double) {
        guard !showActionBar else { return }
        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            withAnimation(.easeIn(duration: 0.4)) { showActionBar = true }
        }
    }

    private func maybeCompleteSplash() {
        guard minTimerDone && webReadyDone else { return }
        withAnimation(.easeOut(duration: 0.4)) { showSplash = false }
    }
}
