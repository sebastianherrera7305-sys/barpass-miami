import Foundation

/// Feature flags for the v17.1 UI redesign. Every V2 screen that replaces an
/// existing V1 screen is gated here so we can roll each one back
/// independently from a UserDefault without a release:
///
///   defaults write com.sebastian.barpass bp_v2_<name>_enabled -bool NO
///
/// Default per flag is `true` once the V2 screen passes TestFlight review.
/// Setting a flag to `false` falls back to the original V1 screen without
/// a code change.
enum V2Flags {
    private static func read(_ key: String, default defaultValue: Bool) -> Bool {
        if UserDefaults.standard.object(forKey: key) == nil { return defaultValue }
        return UserDefaults.standard.bool(forKey: key)
    }

    /// Tab 1 → ExploreV2View in place of ExploreView.
    static var exploreV2: Bool   { read("bp_v2_explore_enabled",   default: true) }
    /// Tab 2 → SocialV2View in place of SocialView.
    static var socialV2: Bool    { read("bp_v2_social_enabled",    default: true) }
    /// Tab 3 → TripsListV2View in place of TripsListView.
    static var tripsListV2: Bool { read("bp_v2_trips_enabled",     default: true) }
    /// Tap on a venue → VenuePulseView in place of VenueDetailView.
    static var venuePulseV2: Bool { read("bp_v2_venue_enabled",    default: true) }
    /// Login → AuthLoginV2View in place of NativeAuthView.
    /// NOT enabled by default — AuthV2 is pure visual, needs its real
    /// email/password/Apple handlers wired before it goes live.
    static var authV2: Bool      { read("bp_v2_auth_enabled",      default: false) }
    /// Priority Entry hub → PriorityEntryV2View in place of PriorityEntryHubView.
    /// NOT enabled by default — V2 is pure visual, callbacks need to be wired
    /// to the existing SkipLine / Table / Tickets flows first.
    static var priorityV2: Bool  { read("bp_v2_priority_enabled",  default: false) }
}
