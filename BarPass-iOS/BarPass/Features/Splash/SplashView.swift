import SwiftUI

struct SplashView: View {
    @ObservedObject private var l10n = L10n.shared
    @EnvironmentObject private var appState: AppState

    @State private var logoOpacity: Double = 0
    @State private var logoY: CGFloat = 12
    @State private var tagOpacity: Double = 0

    /// "VIDA NOCTURNA · MIAMI" — the city half only when the user has
    /// actually chosen one. The app covers 23 cities, so a hardcoded
    /// "MIAMI" was false for most users; showing just the translated word
    /// is the part that's always true.
    private var tagline: String {
        let base = l10n.t("splash.tagline")
        if let city = SelectedCityStore.selectedCity, !city.isEmpty {
            return "\(base) · \(city.uppercased())"
        }
        return base
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Image("BarPassMascot")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 68)
                    .padding(14)
                    .background(Color.white, in: Circle())
                    .padding(.bottom, 8)

                Text("BARPASS")
                    .font(.bpScaled(30, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Text(tagline)
                    .font(.bpScaled(9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.3))
                    .tracking(4)
                    .padding(.top, 12)

                Spacer()
            }
            .opacity(logoOpacity)
            .offset(y: logoY)
        }
        .accessibilityElement(children: .ignore)
        .bpAccessibility(label: "BarPass", hint: l10n.t("splash.loading.hint"))
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
