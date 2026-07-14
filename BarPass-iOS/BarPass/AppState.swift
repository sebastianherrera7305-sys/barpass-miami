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
    @Published var showOnboarding         = false
    @Published var showActionBar          = false
    @Published var showNativeAuth         = true
    @Published var showAgeGate            = false
    @Published var isOffline              = false
    @Published var deepLinkURL:            URL?
    @Published var showCart               = false
    @Published var walletBalance:          Double = 0
    @Published var lastOrderConfirmation:  OrderConfirmation?
    @Published var showPriorityEntry       = false
    @Published var priorityVenueId:        String = ""
    @Published var priorityVenueName:      String = ""
    @Published var appReady                = false

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

    func splashComplete() {
        withAnimation(.easeOut(duration: 0.15)) { showSplash = false }
    }

    /// Called after successful auth (sign in, sign up, or session restore).
    /// Dismisses auth UI, marks app as ready, and reveals the action bar.
    func completeAuth() {
        withAnimation(.easeOut(duration: 0.1)) { showNativeAuth = false }
        appReady = true
        if !AgeGateService.isVerified {
            showAgeGate = true
        } else {
            withAnimation(.easeOut(duration: 0.15).delay(0.1)) { showActionBar = true }
        }
    }

    /// Called once the user confirms they're 21+. Reveals the action bar the
    /// same way completeAuth() would have if the gate hadn't been needed.
    func completeAgeGate() {
        withAnimation(.easeOut(duration: 0.15)) { showAgeGate = false }
        withAnimation(.easeOut(duration: 0.15).delay(0.1)) { showActionBar = true }
    }

}
