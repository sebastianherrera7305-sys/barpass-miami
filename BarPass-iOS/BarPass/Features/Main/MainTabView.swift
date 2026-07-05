import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var cart:     CartStore
    @StateObject private var venueStore = VenueStore()

    @State private var selectedTab = 0

    private let amber = Color(red: 0.92, green: 0.72, blue: 0.28)

    var body: some View {
        ZStack(alignment: .bottom) {
            // Direct switch — paged TabView stole horizontal swipes from the
            // venue carousels and ignored programmatic selection changes.
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
                    PlanView()
                        .environmentObject(venueStore)
                        .environmentObject(appState)
                default:
                    ProfileView()
                        .environmentObject(appState)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
            .id(selectedTab)

            // Custom tab bar
            customTabBar
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var customTabBar: some View {
        HStack(spacing: 0) {
            tabItem(icon: "flame.fill",       label: "Tonight",  index: 0)
            tabItem(icon: "map.fill",         label: "Explore",  index: 1)
            tabItem(icon: "sparkles",         label: "Plan",     index: 2)
            tabItem(icon: "person.fill",      label: "Me",       index: 3)
        }
        .padding(.horizontal, 8)
        .padding(.top, 12)
        .padding(.bottom, 28)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 0.5)
                }
                .ignoresSafeArea()
        )
        .environment(\.colorScheme, .dark)
    }

    private func tabItem(icon: String, label: String, index: Int) -> some View {
        let selected = selectedTab == index
        return Button { withAnimation(.easeInOut(duration: 0.2)) { selectedTab = index } } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? amber : Color.white.opacity(0.35))
                    .scaleEffect(selected ? 1.1 : 1.0)
                    .animation(.spring(response: 0.3), value: selected)

                Text(label)
                    .font(.system(size: 10, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? amber : Color.white.opacity(0.3))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppState())
        .environmentObject(CartStore())
}
