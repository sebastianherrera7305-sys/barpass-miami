import SwiftUI

struct SplashView: View {
    @EnvironmentObject private var appState: AppState
    @State private var logoScale: CGFloat = 0.7
    @State private var logoOpacity: Double = 0
    @State private var taglineOpacity: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var shimmerOffset: CGFloat = -200

    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()

            // Ambient glow
            RadialGradient(
                colors: [Color(hex: "#d4af37").opacity(0.15), .clear],
                center: .center,
                startRadius: 20,
                endRadius: 280
            )
            .ignoresSafeArea()
            .scaleEffect(pulseScale)
            .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: pulseScale)

            VStack(spacing: 24) {
                Spacer()

                // Logo mark
                ZStack {
                    Circle()
                        .fill(Color(hex: "#d4af37").opacity(0.12))
                        .frame(width: 120, height: 120)

                    Circle()
                        .strokeBorder(Color(hex: "#d4af37").opacity(0.3), lineWidth: 1)
                        .frame(width: 120, height: 120)

                    Text("BP")
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "#f5d97e"), Color(hex: "#d4af37")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .scaleEffect(logoScale)
                .opacity(logoOpacity)

                // Wordmark
                VStack(spacing: 6) {
                    Text("BarPass")
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "#f5d97e"), Color(hex: "#d4af37")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .overlay(shimmer)

                    Text("MIAMI NIGHTLIFE")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color(hex: "#d4af37").opacity(0.6))
                        .kerning(4)
                }
                .opacity(taglineOpacity)

                Spacer()

                // Loading indicator
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: "#d4af37").opacity(0.4))
                            .frame(width: 6, height: 6)
                            .scaleEffect(pulseScale)
                            .animation(
                                .easeInOut(duration: 0.6)
                                .repeatForever()
                                .delay(Double(i) * 0.15),
                                value: pulseScale
                            )
                    }
                }
                .opacity(taglineOpacity)
                .padding(.bottom, 60)
            }
        }
        .onAppear {
            pulseScale = 1.15
            withAnimation(.spring(response: 0.7, dampingFraction: 0.65).delay(0.1)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.4)) {
                taglineOpacity = 1.0
            }
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false).delay(0.6)) {
                shimmerOffset = 300
            }
            // Auto-dismiss after web loads
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                appState.splashComplete()
            }
        }
    }

    private var shimmer: some View {
        LinearGradient(
            colors: [.clear, Color.white.opacity(0.25), .clear],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: 80)
        .offset(x: shimmerOffset)
        .blendMode(.overlay)
        .clipped()
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:  (a,r,g,b) = (255,(int>>8)*17,(int>>4&0xF)*17,(int&0xF)*17)
        case 6:  (a,r,g,b) = (255,int>>16,int>>8&0xFF,int&0xFF)
        case 8:  (a,r,g,b) = (int>>24,int>>16&0xFF,int>>8&0xFF,int&0xFF)
        default: (a,r,g,b) = (255,0,0,0)
        }
        self.init(.sRGB,
                  red: Double(r)/255,
                  green: Double(g)/255,
                  blue: Double(b)/255,
                  opacity: Double(a)/255)
    }
}
