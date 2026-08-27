import SwiftUI

/// UI-layer rendering for the `PriceTier` domain value — deliberately kept
/// out of Models/Venue.swift (ADR-014): the model exposes the real 1-4 tier
/// as pure data, the view layer decides how "$"–"$$$$" looks. `nil` for
/// `.unknown` — callers fall back to the shared `venue.crowd.na` l10n key,
/// same pattern as `crowdDescriptionKey`, never a hardcoded default here.
extension PriceTier {
    var symbol: String? {
        switch self {
        case .unknown: return nil
        case .tier1: return "$"
        case .tier2: return "$$"
        case .tier3: return "$$$"
        case .tier4: return "$$$$"
        }
    }
}

extension Font {
    /// Dynamic-Type-aware fixed size: identity at the default content size,
    /// scales with the user's text size setting (UIFontMetrics).
    static func bpScaled(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: UIFontMetrics.default.scaledValue(for: size), weight: weight, design: design)
    }

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
    /// Reduce Motion: the sweep repeats forever, so it's exactly the kind of
    /// perpetual motion the setting exists to stop. The static gradient stays
    /// (it still reads as a placeholder), only the animation is skipped.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    guard !reduceMotion else { return }
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

extension View {
    /// Announces a loading region to VoiceOver as a single element.
    ///
    /// Skeletons are bare `Shape`s, which are not accessibility elements —
    /// so every loading screen was silent, indistinguishable from an empty
    /// or broken view. Labelling each skeleton individually would instead
    /// announce "loading" once per placeholder (7 times on Tonight alone),
    /// so the label belongs on the container that groups them.
    func bpLoadingRegion(_ label: String) -> some View {
        self
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.updatesFrequently)
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

/// Fondo de la app — antes negro/blanco plano en las 24 pantallas, después
/// un glow atmosférico difuminado. Ahora una composición asimétrica de 2-3
/// formas PLANAS con contorno negro grueso por tema (ver
/// `BPTheme.backgroundBlobs`) — el mismo lenguaje "sticker" del logo
/// (relleno plano, línea gruesa, sombra dura) en vez de un degradado suave
/// que le peleaba visualmente al mascot. Un solo punto de cambio para toda
/// la app, cero assets de imagen. `@ObservedObject` en vez de leer el
/// `static var currentPalette` directamente: así se repinta solo apenas
/// cambia la ciudad/tema, sin depender de que algún ancestro fuerce
/// `.id(theme)`.
struct BPBackgroundView: View {
    @ObservedObject private var themeService = ThemeService.shared
    @State private var selectedCity: String? = SelectedCityStore.selectedCity

    var body: some View {
        Group {
            if AppearanceStore.isDark {
                GeometryReader { proxy in
                    if let artName = CityBackgroundArt.imageName(for: selectedCity) {
                        // Real illustrated art for cities that have it —
                        // fills the top of the screen, fades to solid black
                        // well before the safe content area so venue cards/
                        // text never fight it for legibility.
                        ZStack(alignment: .top) {
                            Color.black
                            Image(artName)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: proxy.size.width, height: proxy.size.height * 0.62)
                                .clipped()
                                .overlay(alignment: .bottom) {
                                    // Fade starts earlier (was 0.35) so the
                                    // profile header and the first row of
                                    // Tonight cards — both of which sit
                                    // fairly high on screen — land against
                                    // mostly-faded art instead of the
                                    // brightest part of the illustration.
                                    LinearGradient(
                                        colors: [.clear, .black.opacity(0.55), .black],
                                        startPoint: .init(x: 0.5, y: 0.12),
                                        endPoint: .bottom
                                    )
                                    .frame(height: proxy.size.height * 0.62)
                                }
                            GrainTexture(opacity: 0.03)
                        }
                    } else {
                        let blobs = themeService.theme.backgroundBlobs
                        ZStack {
                            Color.black

                            ForEach(Array(blobs.enumerated()), id: \.offset) { _, blob in
                                // The stroke must NOT inherit the fill's low
                                // opacity — a "black" outline at 45% opacity
                                // just blends into the dark background and
                                // reads as soft, not as the mascot's crisp,
                                // fully-opaque line. Opacity applies to the
                                // fill only; the stroke stays solid black.
                                ZStack {
                                    Circle().fill(blob.color).opacity(blob.opacity)
                                    Circle().strokeBorder(.black, lineWidth: 6)
                                }
                                .frame(width: proxy.size.width * blob.radius, height: proxy.size.width * blob.radius)
                                .position(x: proxy.size.width * blob.point.x, y: proxy.size.height * blob.point.y)
                                .blur(radius: blob.blur)
                            }

                            GrainTexture()
                        }
                    }
                }
            } else {
                Color.bpBackground
            }
        }
        .ignoresSafeArea()
        .onReceive(NotificationCenter.default.publisher(for: .selectedCityChanged)) { note in
            selectedCity = note.object as? String
        }
    }
}

/// Cities with real illustrated background art (generated per-city, not
/// per-theme — Gainesville and Miami share a theme color but not art,
/// since the art is a specific illustrated piece, not just a recolor).
/// Cities without an entry fall back to the flat sticker-blob composition.
enum CityBackgroundArt {
    private static let names: [String: String] = [
        "Miami": "CityArtMiami",
        "New York": "CityArtNewYork",
    ]

    static func imageName(for city: String?) -> String? {
        guard let city else { return nil }
        return names[city]
    }
}

/// A static, deterministic film-grain overlay — a few hundred faint dots,
/// same pattern every render (seeded, not `Double.random`), so it never
/// flickers on re-layout. This one texture pass is what keeps the
/// background glows from reading as a flat, generic gradient blob.
struct GrainTexture: View {
    var opacity: Double = 0.05

    var body: some View {
        Canvas { context, size in
            var rng = SeededGenerator(seed: 42)
            let dotCount = Int((size.width * size.height) / 900)
            for _ in 0..<dotCount {
                let x = CGFloat.random(in: 0...size.width, using: &rng)
                let y = CGFloat.random(in: 0...size.height, using: &rng)
                let a = Double.random(in: 0.03...0.10, using: &rng)
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)), with: .color(.white.opacity(a)))
            }
        }
        .opacity(opacity)
        .allowsHitTesting(false)
    }
}

/// Deterministic PRNG (SplitMix64) so grain/other one-shot texture draws are
/// stable across re-renders instead of using the system RNG, which would
/// reshuffle every dot on every SwiftUI diff. A plain linear-congruential
/// generator was tried first and produced a visible grid/moiré artifact —
/// its low bits are weakly correlated, which `random(in:using:)` exposed
/// directly. SplitMix64 mixes the state through a proper avalanche step
/// before returning it, which is what actually reads as organic grain
/// instead of a repeating dot lattice.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
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
    var showsMascot: Bool = true

    var body: some View {
        VStack(spacing: 10) {
            if showsMascot {
                Image("BarPassMascot")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 46, height: 44)
                    .padding(9)
                    .background(Color.white, in: Circle())
            }

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
            }

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


// MARK: - Hero zoom transition (iOS 18+, no-op on 17)

extension View {
    /// Marks a card as the visual source of the zoom into a detail view.
    @ViewBuilder
    func bpZoomSource(id: String, in ns: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            self.matchedTransitionSource(id: id, in: ns)
        } else { self }
    }

    /// Applies the zoom navigation transition on the destination.
    @ViewBuilder
    func bpZoomDestination(id: String, in ns: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            self.navigationTransition(.zoom(sourceID: id, in: ns))
        } else { self }
    }
}
