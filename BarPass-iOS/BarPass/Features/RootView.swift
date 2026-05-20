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
        }
        .animation(.easeInOut(duration: 0.5), value: appState.showSplash)
    }
}
