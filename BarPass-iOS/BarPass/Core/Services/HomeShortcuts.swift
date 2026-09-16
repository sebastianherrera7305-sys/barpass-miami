import UIKit

/// The four items on the Home Screen icon's long-press menu.
///
/// That menu is also the delete menu — "Delete App" is the last row of the
/// same list — which is the whole point: it is the only surface we own at the
/// moment somebody is about to remove us. So these four are aimed there:
/// one reason to open it instead, one way to tell us what's wrong, whatever
/// the person is actually leaving behind, and the fastest route back in.
///
/// Every line is true. The points and the wallet balance are the user's real
/// numbers, read at the moment the menu is rebuilt, and an item that has no
/// real number to show is replaced rather than filled with a promise —
/// there is no fake "special offer" here, because we have no offer to give
/// and an invented one is a lie that gets found out on the next tap.
///
/// Rebuilt at launch, when the app goes to the background (which is when the
/// numbers were last true, and usually the last thing that happens before
/// someone long-presses the icon), and whenever the language changes.
enum HomeShortcuts {

    @MainActor
    static func install() {
        var items: [UIApplicationShortcutItem] = [
            item("stay", icon: "moon.stars.fill", url: "barpass://prompt"),
            item("feedback", icon: "bubble.left.and.bubble.right.fill", url: "barpass://feedback"),
        ]

        // Third slot: what they'd actually be walking away from, if anything.
        if let holding = holdingItem() {
            items.append(holding)
        } else {
            items.append(item("social", icon: "person.2.fill", url: "barpass://social"))
        }

        items.append(item("explore", icon: "map.fill", url: "barpass://explore"))
        UIApplication.shared.shortcutItems = items
    }

    /// Wallet money first (it is literally theirs), then points. Nil when
    /// both are zero — which is most people, and is exactly when this slot
    /// should hold something else.
    @MainActor
    private static func holdingItem() -> UIApplicationShortcutItem? {
        let balance = AppState.lastKnownWalletBalance
        if balance >= 1 {
            return UIApplicationShortcutItem(
                type: "me",
                localizedTitle: String(format: L10n.tSync("shortcut.wallet"), Int(balance)),
                localizedSubtitle: L10n.tSync("shortcut.wallet.sub"),
                icon: UIApplicationShortcutIcon(systemImageName: "creditcard.fill"),
                userInfo: ["url": "barpass://me" as NSSecureCoding]
            )
        }
        let xp = PointsEngine.shared.totalXP
        guard xp > 0 else { return nil }
        return UIApplicationShortcutItem(
            type: "me",
            localizedTitle: String(format: L10n.tSync("shortcut.points"), xp),
            localizedSubtitle: L10n.tSync("shortcut.points.sub"),
            icon: UIApplicationShortcutIcon(systemImageName: "flame.fill"),
            userInfo: ["url": "barpass://me" as NSSecureCoding]
        )
    }

    @MainActor
    private static func item(_ key: String, icon: String, url: String) -> UIApplicationShortcutItem {
        UIApplicationShortcutItem(
            type: key,
            localizedTitle: L10n.tSync("shortcut.\(key)"),
            localizedSubtitle: L10n.tSync("shortcut.\(key).sub"),
            icon: UIApplicationShortcutIcon(systemImageName: icon),
            userInfo: ["url": url as NSSecureCoding]
        )
    }

    /// The deep link behind a tapped item. Falls back to the item's `type` so
    /// an item created by an older build — iOS stores this menu, not us, and
    /// it survives app updates — still routes somewhere sane.
    static func url(for item: UIApplicationShortcutItem) -> URL? {
        if let raw = item.userInfo?["url"] as? String, let url = URL(string: raw) { return url }
        return URL(string: "barpass://\(item.type)")
    }
}
