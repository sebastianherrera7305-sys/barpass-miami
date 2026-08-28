import SwiftUI
import Combine

/// Lightweight UI themes. One palette = one accent pair; every view keeps
/// using `Color.bpAmber` / `.bpAmberBright` (computed from the active theme),
/// so there are zero duplicated styles. Switching re-renders the whole tree
/// via `.id(theme)` at the MainTabView root.
enum BPTheme: String, CaseIterable, Identifiable {
    case miamiNight = "miami_night"
    case oceanBlue  = "ocean_blue"
    case neon       = "neon"
    case ultra      = "ultra"
    case f1         = "f1"
    case artBasel   = "art_basel"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .miamiNight: return "Miami Night"
        case .oceanBlue:  return "Ocean Blue"
        case .neon:       return "Neon"
        case .ultra:      return "Ultra"
        case .f1:         return "F1"
        case .artBasel:   return "Art Basel"
        }
    }

    /// (accent, accentBright)
    var palette: (Color, Color) {
        switch self {
        case .miamiNight: return (Color(red: 0.92, green: 0.72, blue: 0.28), Color(red: 0.98, green: 0.86, blue: 0.50))
        case .oceanBlue:  return (Color(red: 0.25, green: 0.68, blue: 0.95), Color(red: 0.55, green: 0.85, blue: 1.00))
        case .neon:       return (Color(red: 0.95, green: 0.30, blue: 0.75), Color(red: 1.00, green: 0.55, blue: 0.90))
        case .ultra:      return (Color(red: 0.62, green: 0.40, blue: 0.98), Color(red: 0.78, green: 0.62, blue: 1.00))
        case .f1:         return (Color(red: 0.95, green: 0.22, blue: 0.20), Color(red: 1.00, green: 0.45, blue: 0.40))
        case .artBasel:   return (Color(red: 0.20, green: 0.85, blue: 0.65), Color(red: 0.50, green: 0.95, blue: 0.80))
        }
    }

    /// A hand-composed, asymmetric layout of flat, thick-outlined "sticker"
    /// shapes for BPBackgroundView — deliberately different POSITIONS and
    /// COUNTS per theme, not just a recolor of one centered shape. Flat
    /// fill + hard black outline (near-zero blur) on purpose: this is what
    /// actually matches the mascot artwork's own bold-cartoon, thick-line
    /// style. An earlier soft, heavily-blurred "atmospheric glow" version
    /// looked premium in isolation but fought the flat mascot logo — two
    /// different visual languages on the same screen.
    var backgroundBlobs: [BackgroundBlob] {
        let (accent, bright) = palette
        switch self {
        case .miamiNight:
            // Sunset: warm shape high and right, a second coral shape low-left.
            // Positions keep the full circle (position ± radius/2) inside
            // the screen so the black ring never gets clipped by the edge.
            return [
                BackgroundBlob(point: UnitPoint(x: 0.72, y: 0.20), color: bright, radius: 0.38, opacity: 0.45, blur: 2),
                BackgroundBlob(point: UnitPoint(x: 0.16, y: 0.80), color: Color(red: 0.95, green: 0.45, blue: 0.55), radius: 0.26, opacity: 0.35, blur: 2),
            ]
        case .oceanBlue:
            // Deep sea: large cool shape top-left, a small icy highlight bottom-right.
            return [
                BackgroundBlob(point: UnitPoint(x: 0.24, y: 0.18), color: accent, radius: 0.40, opacity: 0.42, blur: 2),
                BackgroundBlob(point: UnitPoint(x: 0.80, y: 0.75), color: bright, radius: 0.22, opacity: 0.32, blur: 2),
            ]
        case .neon:
            // Vegas strip: three scattered shapes for a busier, electric feel.
            return [
                BackgroundBlob(point: UnitPoint(x: 0.24, y: 0.18), color: accent, radius: 0.30, opacity: 0.44, blur: 2),
                BackgroundBlob(point: UnitPoint(x: 0.80, y: 0.48), color: Color(red: 0.55, green: 0.25, blue: 0.95), radius: 0.28, opacity: 0.40, blur: 2),
                BackgroundBlob(point: UnitPoint(x: 0.44, y: 0.84), color: bright, radius: 0.18, opacity: 0.34, blur: 2),
            ]
        case .ultra:
            // Dreamy: one shape top-center, one deep violet low-left.
            return [
                BackgroundBlob(point: UnitPoint(x: 0.5, y: 0.16), color: bright, radius: 0.40, opacity: 0.40, blur: 2),
                BackgroundBlob(point: UnitPoint(x: 0.18, y: 0.80), color: accent, radius: 0.24, opacity: 0.34, blur: 2),
            ]
        case .f1:
            // Intense: a tight red shape off-center for energy, a small
            // ember low-left. Slightly less blur — this one stays punchy.
            return [
                BackgroundBlob(point: UnitPoint(x: 0.76, y: 0.20), color: accent, radius: 0.30, opacity: 0.48, blur: 2),
                BackgroundBlob(point: UnitPoint(x: 0.14, y: 0.78), color: Color(red: 0.95, green: 0.55, blue: 0.15), radius: 0.20, opacity: 0.32, blur: 2),
            ]
        case .artBasel:
            // Fresh: one elongated teal shape left-center, a bright mint
            // accent top-right.
            return [
                BackgroundBlob(point: UnitPoint(x: 0.24, y: 0.42), color: accent, radius: 0.34, opacity: 0.40, blur: 2),
                BackgroundBlob(point: UnitPoint(x: 0.78, y: 0.18), color: bright, radius: 0.18, opacity: 0.36, blur: 2),
            ]
        }
    }
}

/// One flat "sticker" shape in a theme's background composition — `point`
/// is fractional (0...1) screen position, `radius` is fractional screen
/// width. Near-zero `blur` is intentional (a soft edge, not a glow).
struct BackgroundBlob {
    let point: UnitPoint
    let color: Color
    let radius: CGFloat
    let opacity: Double
    let blur: CGFloat
}

@MainActor
final class ThemeService: ObservableObject {
    static let shared = ThemeService()
    private static let key = "bp_theme"

    /// Read from any context by the Color tokens (plain value, no isolation).
    nonisolated(unsafe) static var currentPalette: (Color, Color) = BPTheme.miamiNight.palette

    @Published var theme: BPTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: Self.key)
            Self.currentPalette = theme.palette
        }
    }

    private var cancellables = Set<AnyCancellable>()

    private init() {
        // A selected city's identity wins over whatever theme was last
        // manually picked — "pick Gainesville, everything's a Gator" means
        // the city is authoritative on relaunch too, not just on first pick.
        let cityTheme = SelectedCityStore.selectedCity.map { CityIdentity.forCity($0).theme }
        let saved = UserDefaults.standard.string(forKey: Self.key)
        let t = cityTheme ?? saved.flatMap(BPTheme.init) ?? .miamiNight
        theme = t
        Self.currentPalette = t.palette

        NotificationCenter.default.publisher(for: .selectedCityChanged)
            .compactMap { $0.object as? String }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] city in self?.theme = CityIdentity.forCity(city).theme }
            .store(in: &cancellables)
    }
}


// MARK: - Appearance (dark / light)

enum BPAppearance: String, CaseIterable, Identifiable {
    case dark, light
    var id: String { rawValue }
    var label: String { self == .dark ? "Oscuro" : "Claro" }
    var emoji: String { self == .dark ? "🌙" : "☀️" }
}

@MainActor
final class AppearanceStore: ObservableObject {
    static let shared = AppearanceStore()
    private static let key = "bp_appearance"

    /// Read by the Color tokens from any context (plain value).
    nonisolated(unsafe) static var isDark: Bool = true

    // Light mode was never actually designed (TestFlight feedback: picking
    // it broke the app — BPBackgroundView's non-dark branch is a flat fill
    // with none of the city art every screen assumes is behind it), and the
    // picker that offered it is gone from ProfileView. `appearance` stays
    // `@Published .dark` unconditionally now, ignoring whatever a device
    // may have persisted under the old key — including a tester's device
    // already stuck on "Claro" from before this fix, which this corrects
    // without them touching anything.
    @Published var appearance: BPAppearance = .dark

    private init() {
        Self.isDark = true
    }
}
