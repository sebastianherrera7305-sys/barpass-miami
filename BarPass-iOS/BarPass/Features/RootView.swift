import SwiftUI

struct RootView: View {
    @ObservedObject private var l10n = L10n.shared
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var cart:     CartStore

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
        // Native floating action bar
        // El botón "⚡ Priority Entry" global vivía acá, visible en las 5
        // tabs para siempre (showActionBar nunca vuelve a false) y sin
        // venueId asociado — abría PriorityEntryHubView con el venue que
        // quedó seteado de la última vez que se vio un detalle, o vacío si
        // nunca se vio ninguno. Priority Entry (skip line/mesa/tickets) es
        // inherentemente por venue — el CTA correcto y ya scopeado vive en
        // VenueDetailView, que sí setea priorityVenueId antes de abrir el
        // sheet. Sacado de acá; ver también la guarda en PriorityEntryHubView.
        .overlay(alignment: .bottom) {
            HStack(spacing: 12) {
                // 🛒 Cart
                Button {
                    appState.showCart = true
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "cart.fill")
                            .font(.bpScaled(18, weight: .semibold))
                            .foregroundStyle(Color.bpInk)
                            .frame(width: 44, height: 44)
                            .background(Color.bpInk.opacity(0.15), in: Circle())
                            .overlay(Circle().strokeBorder(Color.bpInk.opacity(0.2)))

                        if cart.itemCount > 0 {
                            Text("\(cart.itemCount)")
                                .font(.bpScaled(10, weight: .bold))
                                .foregroundStyle(.black)
                                .frame(minWidth: 18, minHeight: 18)
                                .background(Color(red:0.85,green:0.63,blue:0.09), in: Circle())
                                .offset(x: 4, y: -4)
                        }
                    }
                }
                .buttonStyle(.plain)
                .bpAccessibility(label: l10n.t("root.cart"), hint: l10n.t("root.cart.hint"), isButton: true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color(red:0.06,green:0.04,blue:0.10).opacity(0.97))
                    .overlay(Capsule().strokeBorder(Color.bpInk.opacity(0.15), lineWidth: 1))
                    .shadow(color: .black.opacity(0.6), radius: 16, y: 4)
            )
            .padding(.bottom, 100)
            .opacity(appState.showActionBar ? 1 : 0)
            .animation(.easeOut(duration: 0.15), value: appState.showActionBar)
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
        .foregroundStyle(Color.bpInk)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.black.opacity(0.84), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.bpInk.opacity(0.12), lineWidth: 1))
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
                Text(l10n.t("root.orderSent"))
                    .font(.bpScaled(14, weight: .bold))
                    .foregroundStyle(Color.bpInk)
                Text(order.method + " · " + String(format: "$%.2f", order.total))
                    .font(.caption)
                    .foregroundStyle(Color.bpInk.opacity(0.5))
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
