import SwiftUI

extension Font {
    static func bpLargeTitle() -> Font { .system(.largeTitle, design: .rounded).weight(.black) }
    static func bpTitle1() -> Font { .system(.title, design: .rounded).weight(.black) }
    static func bpTitle2() -> Font { .title2.weight(.bold) }
    static func bpHeadline() -> Font { .headline.weight(.bold) }
    static func bpBody() -> Font { .body }
    static func bpCaption() -> Font { .caption.weight(.semibold) }
    static func bpSmall() -> Font { .caption2 }
    static func bpTiny() -> Font { .caption2.weight(.heavy) }
}

struct BPEntranceModifier: ViewModifier {
    let offset: CGSize
    let delay: Double
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(isVisible ? .zero : offset)
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(delay)) {
                    isVisible = true
                }
            }
    }
}

extension View {
    func bpEntrance(offset: CGSize = .zero, delay: Double = 0) -> some View {
        modifier(BPEntranceModifier(offset: offset, delay: delay))
    }

    func bpAccessibility(label: String, hint: String = "", isButton: Bool = false) -> some View {
        self
            .accessibilityLabel(label)
            .accessibilityHint(hint)
            .accessibilityAddTraits(isButton ? .isButton : [])
    }

    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }

    func glass(radius: CGFloat = 14) -> some View {
        self
            .background(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
            .clipShape(RoundedRectangle(cornerRadius: radius))
    }
}

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [.clear, Color.white.opacity(0.08), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase * 200)
                .mask(content)
                .onAppear {
                    withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                        phase = 1
                    }
                }
            )
    }
}

struct ShimmerSkeleton: View {
    var width: CGFloat? = nil
    var height: CGFloat = 14

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.white.opacity(0.06))
            .frame(maxWidth: width == nil ? .infinity : nil)
            .frame(width: width, height: height)
            .shimmer()
    }
}

enum BPRadius {
    static let sm: CGFloat = 10
    static let md: CGFloat = 14
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
}

enum BPSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 14
    static let lg: CGFloat = 20
    static let xl: CGFloat = 28
}

@MainActor enum BPHaptics {
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func medium() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func heavy() { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}

extension Color {
    // Theme-aware accent tokens — the active theme supplies the pair, every
    // view keeps using these names (see ThemeService).
    static var bpAmber: Color { ThemeService.currentPalette.0 }
    static var bpAmberBright: Color { ThemeService.currentPalette.1 }

    // Appearance-aware tokens (dark / light). "Ink" is the primary content
    // color: white on dark, near-black on light. Fills and borders derive
    // from ink so subtle surfaces work in both modes.
    static var bpBackground: Color {
        AppearanceStore.isDark ? .black : Color(red: 0.97, green: 0.96, blue: 0.94)
    }
    static var bpInk: Color {
        AppearanceStore.isDark ? .white : Color(red: 0.09, green: 0.08, blue: 0.12)
    }
    static var bpSurface: Color {
        AppearanceStore.isDark ? Color(white: 0.06) : .white
    }
    static var bpSurfaceRaised: Color {
        AppearanceStore.isDark ? Color(white: 0.08) : Color(white: 0.93)
    }
    static var bpCardBackground: Color {
        AppearanceStore.isDark ? Color(red: 0.06, green: 0.04, blue: 0.10) : .white
    }
    static var bpBorder: Color { bpInk.opacity(0.07) }
    static var bpTextSecondary: Color { bpInk.opacity(AppearanceStore.isDark ? 0.4 : 0.55) }
    static var bpTextTertiary: Color { bpInk.opacity(AppearanceStore.isDark ? 0.25 : 0.4) }
    static let bpGreen = Color(red: 0.2, green: 0.9, blue: 0.4)
    static let bpDanger = Color(red: 1, green: 0.42, blue: 0.42)

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
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

struct BarPassLogo: View {
    var subtitle: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("BAR")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(Color.bpInk)
                Text("PASS")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(Color.bpAmber)
            }
            .tracking(4)

            Rectangle()
                .fill(Color.bpAmber)
                .frame(width: 40, height: 2.5)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(3)
                    .foregroundStyle(Color.bpTextSecondary)
                    .padding(.top, 2)
            }
        }
    }
}
