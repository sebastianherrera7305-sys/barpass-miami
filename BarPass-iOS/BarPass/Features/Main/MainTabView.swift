import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var cart:     CartStore
    @StateObject private var venueStore = VenueStore()
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var themeService = ThemeService.shared
    @ObservedObject private var appearanceStore = AppearanceStore.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedTab = 0
    /// Tracks the previous `appState.isOffline` value so a reconnect refresh
    /// only fires on the actual offline→online transition, not on every
    /// publish of the initial (already-online) value at launch.
    @State private var wasOffline = false
    /// A venue opened from a deep link (`barpass://venue/{id}`). Presented as a
    /// covering detail so it works from any tab without retrofitting the
    /// NavigationLink-based push used inside Tonight/Explore.
    @State private var deepLinkedVenue: BarPassVenue?
    @ObservedObject private var helpStore = HelpGuideStore.shared
    @State private var showHelpIntro = false

    /// The REAL, measured height of whatever's floating at the bottom right
    /// now (tab bar alone, or tab bar + music player) — not a guess. Content
    /// below reserves exactly this much space via `.safeAreaInset`, so it
    /// grows the moment the music player appears/changes height (Dynamic
    /// Type, a longer track title wrapping, etc.) instead of a hardcoded 72
    /// that only ever accounted for the tab bar. 72 here is just the
    /// pre-first-layout-pass fallback, matching the tab bar's typical height
    /// so there's no visible jump on first frame.
    @State private var bottomChromeHeight: CGFloat = 72

    /// nil for tabs with no registered Help content yet (Plan) — the button
    /// simply doesn't render rather than opening an overlay with nothing to
    /// explain.
    private var currentHelpRoute: HelpRoute? {
        switch selectedTab {
        case 0: return .tonight
        case 1: return .explore
        case 2: return .trips
        case 4: return .profile
        default: return nil
        }
    }

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
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: bottomChromeHeight) }

            // Music player + tab bar in ONE stack, top-to-bottom, so their
            // combined height is what gets measured and fed back into the
            // content's bottom inset above — the two floating layers can
            // never silently drift out of sync with what content thinks it
            // needs to clear.
            VStack(spacing: 14) {
                MusicNowPlayingBar()
                    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: MusicNowPlayingObserver.shared.title)
                floatingTabBar
            }
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: BottomChromeHeightPreferenceKey.self, value: geo.size.height)
                }
            )

            // Bottom-trailing, above the tab bar — NOT top-trailing.
            // This is a global overlay drawn on top of whichever screen is
            // showing, and every screen owns its own top-right corner: on
            // Trips it landed exactly on the create-trip button and hid it
            // (TestFlight, build 16: "el botón de ayuda… está justamente
            // encima del botón de crear un trip"). Nothing owns the area just
            // above the tab bar, so one move fixes the collision on every
            // screen instead of nudging them one at a time.
            if let route = currentHelpRoute, !helpStore.isActive {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        HelpButton(route: route)
                            .padding(.trailing, BPSpacing.lg)
                            .padding(.bottom, bottomChromeHeight + BPSpacing.md)
                    }
                }
            }

            if showHelpIntro {
                helpIntroBanner
            }
        }
        .onPreferenceChange(BottomChromeHeightPreferenceKey.self) { height in
            guard height > 0 else { return }
            withAnimation(.easeOut(duration: 0.2)) { bottomChromeHeight = height }
        }
        // Attached to the OUTER ZStack, not the inner Group — anchors from
        // .helpTarget() still bubble up through the whole tree either way,
        // but the resulting overlay must render on top of literally
        // everything (tab bar, music bar, the Help button itself). Reading
        // this preference on the Group alone put the overlay UNDER those —
        // it could activate and never be visible, tap or no tap.
        .overlayPreferenceValue(HelpAnchorPreferenceKey.self) { anchors in
            if helpStore.isActive {
                HelpOverlayView(anchors: anchors)
            }
        }
        .task {
            if helpStore.shouldShowIntro {
                try? await Task.sleep(nanoseconds: 800_000_000)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showHelpIntro = true }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        // Theme switch rebuilds the whole tree so every Color.bpAmber re-resolves.
        .id("\(themeService.theme.rawValue)-\(appearanceStore.appearance.rawValue)")
        .task { await venueStore.loadVenues() }
        // MainTabView only renders once authenticated, so this is the natural
        // point to flush any referral code captured from a pre-auth deep link.
        .task { await ReferralService.shared.attributePendingIfNeeded() }
        // Coming back from background is when venues are most likely stale
        // (user left the app open for a while). loadVenues() is cheap to call
        // here — it only hits the network if the repository's freshness
        // window has actually expired, otherwise it's a no-op cache hit.
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await venueStore.loadVenues() }
            }
        }
        // Reconnecting after being offline should recover on its own — the
        // user shouldn't have to force-quit the app to see current data.
        .onReceive(appState.$isOffline) { offline in
            if wasOffline && !offline {
                Task { await venueStore.loadVenues() }
            }
            wasOffline = offline
        }
        // Deep-link routing. Trip → switch to the Trips tab (TripsListView opens
        // its detail sheet and consumes the route). Venue → resolve + present.
        .onReceive(appState.$pendingRoute.compactMap { $0 }) { route in
            handleDeepLink(route)
        }
        .onReceive(appState.$requestedTab.compactMap { $0 }) { tab in
            selectedTab = tab
            appState.requestedTab = nil
        }
        // Switching tabs while Help is open left `isActive` true but
        // `currentRoute` stuck on the old tab: the overlay kept dimming the
        // new screen while looking for the old screen's tip IDs, which never
        // match, so nothing was ever outlined and the "?" button (hidden
        // while isActive) never came back to let the user retry. Reported as
        // "se queda pegado" — closing on tab change is the actual fix; the
        // instruction banner above is the fallback for when it's still open.
        .onChange(of: selectedTab) { _, _ in
            if helpStore.isActive { helpStore.close() }
        }
        // Cold start: a venue link can arrive before venues finish loading. Retry
        // resolution whenever the catalog updates while a venue route is pending.
        .onReceive(venueStore.$venues) { _ in
            if let route = appState.pendingRoute, case .venue = route {
                handleDeepLink(route)
            }
        }
        .fullScreenCover(item: $deepLinkedVenue) { venue in
            // La Ayuda necesita su propia capa DENTRO del cover. Las
            // preferences de SwiftUI no salen de una presentación modal, así
            // que el `.overlayPreferenceValue` de arriba nunca ve los anchors
            // de esta pantalla: el usuario tocaba "?", `isActive` pasaba a
            // true y el overlay intentaba dibujarse en el árbol de atrás,
            // invisible e intocable. Y como el botón flotante se oculta
            // mientras `isActive` es true, no quedaba forma de apagarlo — la
            // app se sentía trabada. Reportado desde TestFlight.
            NavigationStack { VenueDetailView(venue: venue) }
                .overlayPreferenceValue(HelpAnchorPreferenceKey.self) { anchors in
                    if helpStore.isActive {
                        HelpOverlayView(anchors: anchors)
                    }
                }
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
        case .tonightPrompt:
            selectedTab = 0
            appState.focusPromptRequested = true
            appState.consumeRoute()
        }
    }

    /// First-launch-only, non-blocking — a single small banner, never a
    /// forced tour. Taps either open Help right away or just dismiss.
    private var helpIntroBanner: some View {
        VStack {
            HStack(spacing: 10) {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(Color.bpAmber)
                Text(l10n.t("help.intro.text"))
                    .font(.bpScaled(13, weight: .semibold))
                    .foregroundStyle(Color.bpInk)
                Spacer()
                Button(l10n.t("help.intro.cta")) {
                    BPHaptics.light()
                    helpStore.markIntroShown()
                    withAnimation { showHelpIntro = false }
                    if let route = currentHelpRoute { helpStore.open(route: route) }
                }
                .font(.bpScaled(13, weight: .bold))
                .foregroundStyle(Color.bpAmber)

                Button {
                    BPHaptics.light()
                    helpStore.markIntroShown()
                    withAnimation { showHelpIntro = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.bpScaled(11, weight: .semibold))
                        .foregroundStyle(Color.bpTextSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(BPSpacing.md)
            .glass(radius: BPRadius.lg)
            .overlay(RoundedRectangle(cornerRadius: BPRadius.lg).strokeBorder(Color.bpAmber.opacity(0.2)))
            .shadow(color: .black.opacity(0.35), radius: 14, y: 4)
            .padding(.horizontal, BPSpacing.lg)
            .padding(.top, 104)
            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
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
                // Was this exact colour hardcoded, so the bar stayed dark in
                // Light Mode while its icons/labels use bpInk — dark on dark,
                // i.e. invisible. bpCardBackground is identical in Dark Mode
                // and flips to white in Light, restoring contrast both ways.
                .fill(Color.bpCardBackground.opacity(0.96))
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

/// The real, rendered height of the floating tab bar (+ music player when
/// visible) — read via GeometryReader, never assumed. `reduce` keeps the
/// max in case of any transient double-report during a layout pass.
private struct BottomChromeHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppState())
        .environmentObject(CartStore())
}
