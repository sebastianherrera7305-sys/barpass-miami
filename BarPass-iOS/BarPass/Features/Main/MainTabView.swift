import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var cart:     CartStore
    @StateObject private var venueStore = VenueStore()
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var themeService = ThemeService.shared
    @ObservedObject private var appearanceStore = AppearanceStore.shared

    @State private var selectedTab = 0
    /// A venue opened from a deep link (`barpass://venue/{id}`). Presented as a
    /// covering detail so it works from any tab without retrofitting the
    /// NavigationLink-based push used inside Tonight/Explore.
    @State private var deepLinkedVenue: BarPassVenue?

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case 0:
                    TonightView()
                        .environmentObject(venueStore)
                        .environmentObject(appState)
                case 1:
                    ExploreView()
                        .environmentObject(venueStore)
                case 2:
                    TripsListView()
                        .environmentObject(venueStore)
                case 3:
                    PlanView()
                        .environmentObject(venueStore)
                        .environmentObject(appState)
                default:
                    ProfileView()
                        .environmentObject(appState)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 72) }

            MusicNowPlayingBar()
                .padding(.bottom, 86)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: MusicNowPlayingObserver.shared.title)

            floatingTabBar
        }
        .ignoresSafeArea(edges: .bottom)
        // Theme switch rebuilds the whole tree so every Color.bpAmber re-resolves.
        .id("\(themeService.theme.rawValue)-\(appearanceStore.appearance.rawValue)")
        .task { await venueStore.loadVenues() }
        // MainTabView only renders once authenticated, so this is the natural
        // point to flush any referral code captured from a pre-auth deep link.
        .task { await ReferralService.shared.attributePendingIfNeeded() }
        // Deep-link routing. Trip → switch to the Trips tab (TripsListView opens
        // its detail sheet and consumes the route). Venue → resolve + present.
        .onReceive(appState.$pendingRoute.compactMap { $0 }) { route in
            handleDeepLink(route)
        }
        // Cold start: a venue link can arrive before venues finish loading. Retry
        // resolution whenever the catalog updates while a venue route is pending.
        .onReceive(venueStore.$venues) { _ in
            if let route = appState.pendingRoute, case .venue = route {
                handleDeepLink(route)
            }
        }
        .fullScreenCover(item: $deepLinkedVenue) { venue in
            NavigationStack { VenueDetailView(venue: venue) }
        }
    }

    /// Acts on a parsed deep-link route using the existing navigation surfaces.
    /// Unwired route types (pass/invite/profile) are cleared rather than left to
    /// dead-end — S1 only navigates trip and venue.
    private func handleDeepLink(_ route: DeepLinkRoute) {
        switch route {
        case .trip:
            selectedTab = 2 // TripsListView observes pendingRoute and opens the sheet.
        case .venue(let id):
            if let venue = venueStore.venues.first(where: { $0.id == id }) {
                deepLinkedVenue = venue
                appState.consumeRoute()
            }
            // Not found yet → leave pending; venueStore.$venues retries on load.
        case .invite(let code):
            // Hold the referral code across the (possible) pre-auth → post-auth
            // boundary; attribution is a server call made once a session exists.
            ReferralService.shared.capturePendingCode(code)
            appState.consumeRoute()
        case .pass, .profile:
            appState.consumeRoute()
        }
    }

    private var floatingTabBar: some View {
        HStack(spacing: 0) {
            ForEach(0..<5) { i in
                tabButton(index: i)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color(red: 0.06, green: 0.04, blue: 0.10).opacity(0.96))
                .overlay(Capsule().strokeBorder(Color.bpInk.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
        )
        .padding(.horizontal, 40)
        .padding(.bottom, 6)
    }

    private func tabButton(index: Int) -> some View {
        let isSelected = selectedTab == index
        let items: [(icon: String, label: String)] = [
            ("flame.fill",    l10n.t("tab.tonight")),
            ("map.fill",      l10n.t("tab.explore")),
            ("suitcase.fill", l10n.t("tab.trips")),
            ("sparkles",      l10n.t("tab.plan")),
            ("person.fill",   l10n.t("tab.me")),
        ]
        let item = items[index]

        return Button {
            BPHaptics.light()
            let screenNames = ["Tonight", "Explore", "Trips", "Plan", "Profile"]
            BPAnalytics.screen(screenNames[index])
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                selectedTab = index
            }
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    if isSelected {
                        Capsule()
                            .fill(Color.bpAmber.opacity(0.15))
                            .frame(width: 36, height: 28)
                            .transition(.scale.combined(with: .opacity))
                    }
                    Image(systemName: item.icon)
                        .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.bpAmber : Color.bpInk.opacity(0.3))
                }
                .frame(height: 28)

                Text(item.label)
                    .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.bpAmber : Color.bpInk.opacity(0.25))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .bpAccessibility(
            label: ["Esta noche", "Explorar", "Viajes", "Planificar", "Perfil"][index],
            hint: ["Eventos de esta noche", "Explorar lugares", "Tus viajes", "Planificar tu noche", "Tu perfil"][index],
            isButton: true
        )
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppState())
        .environmentObject(CartStore())
}
