import UIKit

/// The four actions on the Home Screen icon's long-press menu.
///
/// Every one of them is a real destination the app already has, reached in
/// one tap from a cold start instead of two or three. They are built at
/// runtime rather than declared in Info.plist for one reason: the app picks
/// its language itself (L10n, three of them), and static Info.plist entries
/// are localized by the system's language, which is not always the same.
/// Rebuilt whenever the user changes language.
enum HomeShortcuts {

    private enum Action: String, CaseIterable {
        case prompt, explore, social, passes

        var url: String { "barpass://\(rawValue)" }

        var icon: UIApplicationShortcutIcon {
            switch self {
            case .prompt:  return UIApplicationShortcutIcon(systemImageName: "sparkles")
            case .explore: return UIApplicationShortcutIcon(systemImageName: "map.fill")
            case .social:  return UIApplicationShortcutIcon(systemImageName: "person.2.fill")
            case .passes:  return UIApplicationShortcutIcon(systemImageName: "ticket.fill")
            }
        }

        var titleKey: String { "shortcut.\(rawValue)" }
        var subtitleKey: String { "shortcut.\(rawValue).sub" }
    }

    @MainActor
    static func install() {
        UIApplication.shared.shortcutItems = Action.allCases.map { action in
            UIApplicationShortcutItem(
                type: action.rawValue,
                localizedTitle: L10n.tSync(action.titleKey),
                localizedSubtitle: L10n.tSync(action.subtitleKey),
                icon: action.icon,
                userInfo: ["url": action.url as NSSecureCoding]
            )
        }
    }

    /// The deep link behind a tapped item. Falls back to rebuilding it from
    /// the item's `type` so an item created by an older build — the menu is
    /// stored by iOS, not by us, and survives updates — still routes.
    static func url(for item: UIApplicationShortcutItem) -> URL? {
        if let raw = item.userInfo?["url"] as? String, let url = URL(string: raw) { return url }
        return URL(string: "barpass://\(item.type)")
    }
}
