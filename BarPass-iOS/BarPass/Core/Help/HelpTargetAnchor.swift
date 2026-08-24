import SwiftUI

/// Collects `elementID → frame anchor` up the view tree — the mechanism
/// that lets `HelpOverlayView` highlight an arbitrary element without the
/// screen that owns it knowing anything about the overlay. Native
/// SwiftUI (`anchorPreference`), no third-party layout library.
struct HelpAnchorPreferenceKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Registers this view as an explainable Help target. A screen calls
    /// this once per element it wants explainable; it never needs to know
    /// whether Help is active, what the tooltip says, or where the overlay
    /// decides to draw it.
    func helpTarget(_ id: String) -> some View {
        anchorPreference(key: HelpAnchorPreferenceKey.self, value: .bounds) { anchor in
            [id: anchor]
        }
    }
}
