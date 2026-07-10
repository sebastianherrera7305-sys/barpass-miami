import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var cart:     CartStore
    @StateObject private var venueStore = VenueStore()
    @ObservedObject private var l10n = L10n.shared

    @State private var selectedTab = 0

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

            floatingTabBar
        }
        .ignoresSafeArea(edges: .bottom)
        .task { await venueStore.loadVenues() }
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
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
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
                        .foregroundStyle(isSelected ? Color.bpAmber : Color.white.opacity(0.3))
                }
                .frame(height: 28)

                Text(item.label)
                    .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.bpAmber : Color.white.opacity(0.25))
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
