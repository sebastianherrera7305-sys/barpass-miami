import SwiftUI

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

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.key)
        let t = saved.flatMap(BPTheme.init) ?? .miamiNight
        theme = t
        Self.currentPalette = t.palette
    }
}
