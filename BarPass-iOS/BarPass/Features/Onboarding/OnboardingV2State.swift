import Foundation

/// Persistencia + kill switch del OnboardingV2.
///
/// - `useV2`: por default true (ya convergido). Un UserDefault lo apaga en
///   caliente si algo sale mal — ver bp_onboarding_v2_enabled.
/// - `isCompleted`: por device, se marca al terminar las 7 pantallas o al
///   skipearlas desde la intro.
enum OnboardingV2State {
    private static let completedKey = "bp_onboarding_v2_completed"
    private static let enabledKey   = "bp_onboarding_v2_enabled"

    static var useV2: Bool {
        // Default true unless the kill switch is explicitly set to NO.
        if UserDefaults.standard.object(forKey: enabledKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: enabledKey)
    }

    static var isCompleted: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }

    static func markCompleted() {
        UserDefaults.standard.set(true, forKey: completedKey)
    }

    /// For debugging / support — resets the "I've seen onboarding v2" flag
    /// so the user sees it again on next launch. NOT bound to UI yet; call
    /// from a debug menu when it exists.
    static func resetForTesting() {
        UserDefaults.standard.removeObject(forKey: completedKey)
    }
}
