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
    /// Quiz de gustos, entre el video de onboarding y el login. Va antes del
    /// auth a propósito (ver TasteQuizView), así que se resuelve contra
    /// UserDefaults y no contra el usuario, que todavía no existe.
    @Published var showTasteQuiz          = !TasteProfileService.isCompleted
    @Published var showActionBar          = false
    @Published var showNativeAuth         = true
    @Published var showAgeGate            = false
    @Published var showCityPicker         = false
    @Published var showEmailVerification  = false
    @Published var isOffline              = false
    @Published var deepLinkURL:            URL?
    /// The parsed, navigable destination for the most recent deep link, if it
    /// mapped to a supported route. Consumers (MainTabView, TripsListView) act
    /// on it and call `consumeRoute()` to clear it. Nil when there's no pending
    /// deep-link navigation.
    @Published var pendingRoute:           DeepLinkRoute?
    @Published var showCart               = false
    /// Set by a nested screen (e.g. a university's "nightlife nearby" row)
    /// that wants to jump to a top-level tab. MainTabView observes this and
    /// clears it after switching — never push a tab-root view (ExploreView,
    /// TripsListView, etc.) as a child of a NavigationLink; those views own
    /// their own map/search state and aren't designed to be nested.
    @Published var requestedTab:           Int?
    /// Set when `.tonightPrompt` is consumed (widget "prompt" button) —
    /// TonightView passes this down to PromptYourNightHomeSection, which
    /// focuses its text field on `true` and flips it back to `false`.
    @Published var focusPromptRequested    = false
    @Published var walletBalance:          Double = 0
    @Published var lastOrderConfirmation:  OrderConfirmation?
    @Published var showPriorityEntry       = false
    @Published var priorityVenueId:        String = ""
    @Published var priorityVenueName:      String = ""
    /// Set when the user tapped a specific event flyer (not the generic
    /// "Skip the Line" CTA) — lets EventTicketsView sell a ticket for that
    /// real event (real cover price, real student price) instead of always
    /// fabricating a placeholder "tonight" event with no connection to
    /// anything actually happening at the venue.
    @Published var priorityEvent:          VenueEvent?
    @Published var appReady                = false

    private var cancellables = Set<AnyCancellable>()
    private let networkMonitor = NWPathMonitor()
    private let networkQueue   = DispatchQueue(label: "io.barpass.appstate.network", qos: .utility)

    init() {
        NotificationCenter.default.publisher(for: .deepLinkReceived)
            .compactMap { $0.object as? URL }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] url in
                self?.deepLinkURL = url
                self?.pendingRoute = DeepLinkRouter.parse(url)
            }
            .store(in: &cancellables)

        networkMonitor.pathUpdateHandler = { [weak self] path in
            let offline = path.status != .satisfied
            Task { @MainActor in self?.isOffline = offline }
        }
        networkMonitor.start(queue: networkQueue)
    }

    /// Clears the pending deep-link route once a consumer has navigated to it,
    /// so it doesn't re-fire on the next view refresh.
    func consumeRoute() { pendingRoute = nil }

    func splashComplete() {
        withAnimation(.easeOut(duration: 0.15)) { showSplash = false }
    }

    /// Se llama cuando el usuario termina o saltea el quiz de gustos. No
    /// necesita empujar el paso siguiente: `showNativeAuth` ya viene en true,
    /// y RootView lo muestra en cuanto este flag baja.
    func completeTasteQuiz() {
        withAnimation(.easeOut(duration: 0.15)) { showTasteQuiz = false }
    }

    /// Called after successful auth (sign in, sign up, or session restore).
    /// Dismisses auth UI, marks app as ready, and reveals the action bar —
    /// unless the account's email isn't verified yet, in which case it blocks
    /// on the verification screen first. Guest mode (no session at all) skips
    /// this entirely since there's no email to verify.
    ///
    /// The cached session's `emailConfirmedAt` can be stale (e.g. accounts
    /// signed up before this field existed locally, even though Supabase
    /// already had it confirmed server-side) — so an unverified cache is
    /// double-checked against Supabase directly before actually gating
    /// anyone. A network failure during that check fails open (lets the
    /// already-authenticated user in) rather than locking out a real user
    /// over a connectivity blip; the gate re-evaluates on the next launch.
    func completeAuth() {
        withAnimation(.easeOut(duration: 0.1)) { showNativeAuth = false }
        appReady = true
        guard let session = AuthService.shared.restoreSession() else {
            proceedPastAuth()
            return
        }
        if session.isEmailVerified {
            proceedPastAuth()
            return
        }
        Task {
            do {
                let fresh = try await AuthService.shared.refreshUserStatus()
                await MainActor.run {
                    if fresh.isEmailVerified {
                        self.proceedPastAuth()
                    } else {
                        self.showEmailVerification = true
                    }
                }
            } catch {
                await MainActor.run { self.proceedPastAuth() }
            }
        }
    }

    /// Called once the "I've verified my email" check confirms the account
    /// is verified. Continues exactly where completeAuth() would have.
    func completeEmailVerification() {
        withAnimation(.easeOut(duration: 0.15)) { showEmailVerification = false }
        proceedPastAuth()
    }

    private func proceedPastAuth() {
        refreshWalletBalance()
        if !AgeGateService.isVerified {
            showAgeGate = true
        } else {
            proceedPastAgeGate()
        }
    }

    /// Called once the user confirms they're 21+. Continues to the city
    /// picker (or straight to the app) the same way proceedPastAuth() would
    /// have if the age gate hadn't been needed.
    func completeAgeGate() {
        withAnimation(.easeOut(duration: 0.15)) { showAgeGate = false }
        proceedPastAgeGate()
    }

    /// A city choice is required before the action bar/main app appears —
    /// without it every city's venues render mixed together with no way to
    /// tell them apart. Only asked once per install; changeable later from
    /// Profile via SelectedCityStore.reset() + select().
    private func proceedPastAgeGate() {
        if SelectedCityStore.selectedCity == nil {
            showCityPicker = true
        } else {
            withAnimation(.easeOut(duration: 0.15).delay(0.1)) { showActionBar = true }
        }
    }

    /// Called once the user picks a city (or confirms there was only one to
    /// pick). Reveals the action bar the same way completeAgeGate() would have.
    func completeCityPicker() {
        withAnimation(.easeOut(duration: 0.15)) { showCityPicker = false }
        withAnimation(.easeOut(duration: 0.15).delay(0.1)) { showActionBar = true }
    }

    /// Clears per-user state left over from the previous session so it can't
    /// be read (even briefly) once a different account signs in. Call this
    /// alongside AuthService.shared.signOut().
    func resetUserState() {
        walletBalance = 0
        priorityVenueId = ""
        priorityVenueName = ""
        priorityEvent = nil
        showActionBar = false
        showAgeGate = false
        showCityPicker = false
        showEmailVerification = false
        lastOrderConfirmation = nil
        showPriorityEntry = false
        showCart = false
    }

    /// Pulls the real balance from Supabase — walletBalance always starts at
    /// 0 locally, so this is the only thing that should ever raise it,
    /// besides a successful top-up's direct response.
    func refreshWalletBalance() {
        guard let session = AuthService.shared.restoreSession() else { return }
        Task {
            // A failed fetch (nil) leaves walletBalance exactly as it was —
            // overwriting it with 0 made a real balance disappear from the
            // UI on any transient network blip, indistinguishable from
            // having actually spent it all.
            guard let balance = await WalletService.fetchBalance(session: session) else { return }
            await MainActor.run { self.walletBalance = balance }
        }
    }
}
