import SwiftUI

/// An AppState you can ask for without crashing if it isn't there.
///
/// `@EnvironmentObject` traps when the object is missing — it has no optional
/// form and no way to check first. That is a reasonable default for a screen
/// with exactly one parent, and a liability for one presented from six places,
/// several inside a `.sheet` or `.fullScreenCover` where the environment is
/// least predictable. UniversityDetailView crashed exactly that way on build
/// 71 ("EnvironmentObject.error", iOS 26.3) on the line that read one, AFTER
/// MainTabView had been changed to inject it into every tab.
///
/// This key defaults to nil, so a screen that wants AppState can degrade —
/// hide the action it cannot perform — instead of taking the app down. Inject
/// it with `.appState(appState)` anywhere the real one exists.
private struct AppStateKey: EnvironmentKey {
    static let defaultValue: AppState? = nil
}

extension EnvironmentValues {
    var appStateIfPresent: AppState? {
        get { self[AppStateKey.self] }
        set { self[AppStateKey.self] = newValue }
    }
}

extension View {
    /// Supplies AppState through the environment in a form that a child can
    /// read without risking a trap.
    func appState(_ state: AppState) -> some View {
        environment(\.appStateIfPresent, state)
    }
}
