import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            BarPassWebContainerView()
                .ignoresSafeArea()
                .opacity(appState.showSplash ? 0 : 1)

            if appState.showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
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
        .animation(.easeInOut(duration: 0.5), value: appState.showSplash)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: appState.isOffline)
    }
}

private struct OfflineBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.caption.weight(.bold))
            Text("Sin conexión — usando versión local")
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.black.opacity(0.84), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 3)
    }
}
