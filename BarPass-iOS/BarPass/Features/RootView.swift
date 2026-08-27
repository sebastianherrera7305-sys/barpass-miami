import SwiftUI

struct RootView: View {
    @ObservedObject private var l10n = L10n.shared
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var cart:     CartStore
    @ObservedObject private var checkInStore = CheckInStore.shared

    var body: some View {
        ZStack {
            // Native main experience. Built only AFTER auth: at opacity 0 it
            // still rendered 181 venue cards behind the login, saturating the
            // main thread and making the login feel frozen.
            if !appState.showSplash && !appState.showNativeAuth {
                NavigationStack {
                    MainTabView()
                }
                .ignoresSafeArea()
                .transition(.opacity)
                .task { await AppleMusicPlaybackService.playTopSongs() }
            } else {
                BPBackgroundView()
            }

            if appState.showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }

            if appState.showOnboarding && !appState.showSplash {
                OnboardingVideoView()
                    .transition(.opacity)
                    .zIndex(4)
            }

            if appState.showNativeAuth && !appState.showOnboarding {
                NativeAuthView()
                    .environmentObject(appState)
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
                    .zIndex(5)
            }

            if appState.showEmailVerification {
                VerifyEmailView { appState.completeEmailVerification() }
                    .transition(.opacity)
                    .zIndex(6)
            }

            if appState.showAgeGate {
                AgeGateView { appState.completeAgeGate() }
                    .transition(.opacity)
                    .zIndex(6)
            }

            if appState.showCityPicker {
                CityPickerView { appState.completeCityPicker() }
                    .transition(.opacity)
                    .zIndex(7)
            }

            if appState.isOffline && !appState.showSplash {
                VStack {
                    Spacer()
                    OfflineBanner()
                        .padding(.bottom, 100)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .zIndex(2)
            }
        }
        .animation(.easeOut(duration: 0.1), value: appState.showSplash)
        .animation(.spring(response: 0.2, dampingFraction: 0.85), value: appState.isOffline)
        .animation(.easeOut(duration: 0.1), value: appState.showNativeAuth)
        // Floating cart button — only exists when there's actually something
        // to show (cart.itemCount > 0). Previously this was an always-on
        // overlay gated by showActionBar, which the code's own comment
        // admitted never returns to false — so it rendered on every screen
        // in the app, including flows with nothing to do with a cart (e.g.
        // Greek Life sign-up). Small and corner-anchored per explicit
        // request, not the old center pill.
        .overlay(alignment: .bottomTrailing) {
            VStack(spacing: 12) {
                // "Go home" — only while checked in somewhere (per explicit
                // product decision: not useful outside a real night out).
                if checkInStore.activeCheckin != nil {
                    GoHomeButton()
                }
                if appState.showActionBar && cart.itemCount > 0 {
                    Button {
                        appState.showCart = true
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "cart.fill")
                                .font(.bpScaled(14, weight: .semibold))
                                .foregroundStyle(Color.bpInk)
                                .frame(width: 34, height: 34)
                                .background(Color.bpCardBackground.opacity(0.97), in: Circle())
                                .overlay(Circle().strokeBorder(Color.bpInk.opacity(0.15), lineWidth: 1))
                                .shadow(color: .black.opacity(0.5), radius: 10, y: 3)

                            Text("\(cart.itemCount)")
                                .font(.bpScaled(9, weight: .bold))
                                .foregroundStyle(.black)
                                .frame(minWidth: 15, minHeight: 15)
                                .background(Color(red: 0.85, green: 0.63, blue: 0.09), in: Circle())
                                .offset(x: 3, y: -3)
                        }
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                    .bpAccessibility(label: l10n.t("root.cart"), hint: l10n.t("root.cart.hint"), isButton: true)
                }
            }
            .padding(.trailing, 16)
            .padding(.bottom, 100)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: cart.itemCount)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: checkInStore.activeCheckin?.checkinId)
        .task { await checkInStore.load() }
        // Retries AgeGateView's fire-and-forget birthdate write — every
        // profile in the DB showed a null birthdate despite the local gate
        // having been passed, because that write has no retry today. Cheap
        // to check (UserDefaults) and only hits the network when the
        // previous attempt actually never landed.
        .task {
            guard AgeGateService.isVerified, !AgeGateService.isSyncedToServer,
                  let dob = AgeGateService.storedDateOfBirth else { return }
            if (try? await RepositoryDependencies.birthdate.setBirthdate(dob)) != nil {
                AgeGateService.isSyncedToServer = true
            }
        }
        // Native cart sheet
        .sheet(isPresented: $appState.showCart) {
            CartView()
                .environmentObject(cart)
                .environmentObject(appState)
        }
        // Priority Entry hub sheet
        .sheet(isPresented: $appState.showPriorityEntry) {
            PriorityEntryHubView(
                venueId:   appState.priorityVenueId,
                venueName: appState.priorityVenueName
            )
            .environmentObject(appState)
        }
        // Order confirmation toast
        .overlay(alignment: .bottom) {
            if let order = appState.lastOrderConfirmation {
                OrderConfirmationBanner(order: order)
                    .padding(.bottom, 110)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                            withAnimation { appState.lastOrderConfirmation = nil }
                        }
                    }
                    .zIndex(5)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: appState.lastOrderConfirmation)
    }
}

// MARK: - Offline banner

private struct OfflineBanner: View {
    @ObservedObject private var l10n = L10n.shared
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.caption.weight(.bold))
            Text(l10n.t("root.offline"))
                .font(.caption.weight(.medium))
        }
        // Hardcoded-dark background regardless of app appearance — bpInk
        // (near-black in Light Mode) was unreadable against it. Same bug
        // class as HeroVenueCard's photo scrim: text color must be fixed
        // light, not theme-aware, whenever the surface behind it is
        // hardcoded dark on purpose.
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.black.opacity(0.84), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 3)
        .accessibilityElement(children: .ignore)
        .bpAccessibility(label: l10n.t("root.offline.a11y"), hint: l10n.t("root.offline.hint"))
    }
}

// MARK: - Order confirmation banner

private struct OrderConfirmationBanner: View {
    let order: OrderConfirmation
    @ObservedObject private var l10n = L10n.shared
    private let gold = Color(red: 0.85, green: 0.63, blue: 0.09)

    var body: some View {
        HStack(spacing: 12) {
            Text("🚀").font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                // Same hardcoded-dark-background bug as OfflineBanner above —
                // this card's fill (below) never changes with app appearance.
                Text(l10n.t("root.orderSent"))
                    .font(.bpScaled(14, weight: .bold))
                    .foregroundStyle(.white)
                Text(order.method + " · " + String(format: "$%.2f", order.total))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            Text(l10n.t("root.orderEta"))
                .font(.caption.weight(.bold))
                .foregroundStyle(gold)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.08, green: 0.06, blue: 0.10).opacity(0.97))
                .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
        )
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(gold.opacity(0.25), lineWidth: 1))
        .padding(.horizontal, 16)
    }
}
