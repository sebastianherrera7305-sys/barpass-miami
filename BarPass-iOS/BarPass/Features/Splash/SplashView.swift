import SwiftUI

struct SplashView: View {
    @EnvironmentObject private var appState: AppState

    @State private var ringScale:    CGFloat = 0.6
    @State private var ringOpacity:  Double  = 0
    @State private var logoOpacity:  Double  = 0
    @State private var logoY:        CGFloat = 12
    @State private var wordOpacity:  Double  = 0
    @State private var tagOpacity:   Double  = 0
    @State private var barWidth:     CGFloat = 0
    @State private var pulseOpacity: Double  = 0

    private let amber = Color(red: 0.92, green: 0.72, blue: 0.28)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            RadialGradient(
                colors: [.clear, Color.black.opacity(0.55)],
                center: .center,
                startRadius: 160,
                endRadius: 420
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // ── Logo mark ──
                ZStack {
                    Circle()
                        .strokeBorder(amber.opacity(0.12), lineWidth: 1)
                        .frame(width: 110, height: 110)
                        .scaleEffect(ringScale)
                        .opacity(pulseOpacity)

                    Circle()
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                        .frame(width: 86, height: 86)
                        .opacity(ringOpacity)

                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.04))
                        .frame(width: 64, height: 64)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                        )

                    Text("BP")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [amber, Color(red: 0.98, green: 0.86, blue: 0.50)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .opacity(logoOpacity)
                .offset(y: logoY)

                Spacer().frame(height: 28)

                // ── Wordmark ──
                VStack(spacing: 8) {
                    Text("BarPass")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .kerning(-0.5)

                    Text("NIGHTLIFE · MIAMI")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.3))
                        .kerning(4)
                }
                .opacity(wordOpacity)

                Spacer().frame(height: 60)

                // ── Loading bar ──
                VStack(spacing: 12) {
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.06))
                            .frame(width: 120, height: 2)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [amber, Color(red: 0.98, green: 0.86, blue: 0.50)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: barWidth, height: 2)
                    }

                    Text("Cargando tu noche...")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.2))
                }
                .opacity(tagOpacity)

                Spacer()
            }
        }
        .onAppear { runSequence() }
    }

    private func runSequence() {
        withAnimation(.easeOut(duration: 0.5).delay(0.1)) {
            ringOpacity = 1
        }
        withAnimation(.spring(response: 0.65, dampingFraction: 0.72).delay(0.2)) {
            logoOpacity = 1
            logoY       = 0
        }
        withAnimation(.easeOut(duration: 0.45).delay(0.55)) {
            wordOpacity = 1
        }
        withAnimation(.easeOut(duration: 0.3).delay(0.8)) {
            tagOpacity = 1
        }
        withAnimation(.easeInOut(duration: 3.5).delay(0.9)) {
            barWidth = 120
        }
        withAnimation(.easeOut(duration: 0.4).delay(0.6)) {
            pulseOpacity = 1
        }
        withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true).delay(0.8)) {
            ringScale = 1.18
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            appState.splashMinTimerFired()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 7.0) {
            appState.splashComplete()
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:  (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB,
                  red:     Double(r) / 255,
                  green:   Double(g) / 255,
                  blue:    Double(b) / 255,
                  opacity: Double(a) / 255)
    }
}
