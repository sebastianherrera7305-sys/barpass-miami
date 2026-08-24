import SwiftUI

/// Per-feature "have I explained this already" state, plus the overlay's own
/// active/route state. Same UserDefaults-backed singleton pattern as
/// `FavoritesStore` — nothing new architecturally.
@MainActor
final class HelpGuideStore: ObservableObject {
    static let shared = HelpGuideStore()

    private static let seenVersionsKey = "bp_help_seen_versions"   // [tipID: version]
    private static let introShownKey = "bp_help_intro_shown"

    /// Active overlay state — a screen becomes "current" by setting this
    /// when the user opens Help while that screen is on-screen (see
    /// `MainTabView`'s Help button).
    @Published var isActive = false
    @Published var currentRoute: HelpRoute = .tonight

    /// [tipID: last-seen version]. A tip whose `HelpRegistry` version is
    /// higher than what's stored here counts as unseen — the mechanism
    /// requested for "resurface tips that changed after a major update."
    @Published private(set) var seenVersions: [String: Int]

    private init() {
        seenVersions = (UserDefaults.standard.dictionary(forKey: Self.seenVersionsKey) as? [String: Int]) ?? [:]
    }

    func hasSeen(_ tip: HelpTip) -> Bool {
        (seenVersions[tip.id] ?? 0) >= tip.version
    }

    func markAsSeen(_ tip: HelpTip) {
        seenVersions[tip.id] = tip.version
        UserDefaults.standard.set(seenVersions, forKey: Self.seenVersionsKey)
    }

    /// Dev/QA reset — also referenced by the "reset onboarding" ask.
    func resetGuide() {
        seenVersions = [:]
        UserDefaults.standard.removeObject(forKey: Self.seenVersionsKey)
        UserDefaults.standard.removeObject(forKey: Self.introShownKey)
    }

    // MARK: - First-launch mini intro ("Let us show you around")

    var shouldShowIntro: Bool {
        !UserDefaults.standard.bool(forKey: Self.introShownKey)
    }

    func markIntroShown() {
        UserDefaults.standard.set(true, forKey: Self.introShownKey)
    }

    func open(route: HelpRoute) {
        currentRoute = route
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { isActive = true }
    }

    func close() {
        withAnimation(.easeOut(duration: 0.2)) { isActive = false }
    }
}
