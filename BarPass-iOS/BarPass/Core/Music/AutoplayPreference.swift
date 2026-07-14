import Foundation

/// Apagado real y persistente del autoplay — el botón X de la barra
/// "now playing" solo detiene la sesión actual; esto controla si vuelve
/// a sonar la próxima vez que se abre la app.
@MainActor
final class AutoplayPreference: ObservableObject {
    static let shared = AutoplayPreference()
    private static let key = "bp_music_autoplay_enabled"

    /// Leída por AppleMusicPlaybackService fuera de contexto @MainActor-friendly.
    nonisolated(unsafe) static var isEnabled: Bool = true

    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Self.key)
            Self.isEnabled = enabled
        }
    }

    private init() {
        let saved = UserDefaults.standard.object(forKey: Self.key) as? Bool
        let value = saved ?? true
        enabled = value
        Self.isEnabled = value
    }
}
