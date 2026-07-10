import SwiftUI

struct SplashView: View {
    @EnvironmentObject private var appState: AppState

    @State private var logoOpacity: Double = 0
    @State private var logoY: CGFloat = 12
    @State private var tagOpacity: Double = 0

    private let amber = Color(red: 0.92, green: 0.72, blue: 0.28)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Text("BP")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [amber, Color(red: 0.98, green: 0.86, blue: 0.50)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .padding(.bottom, 8)

                Text("BARPASS")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Text("NIGHTLIFE · MIAMI")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.3))
                    .tracking(4)
                    .padding(.top, 12)

                Spacer()
            }
            .opacity(logoOpacity)
            .offset(y: logoY)
        }
        .onAppear {
            withAnimation(.spring(response: 0.15, dampingFraction: 0.85)) {
                logoOpacity = 1
                logoY = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                appState.splashComplete()
            }
        }
    }
}
