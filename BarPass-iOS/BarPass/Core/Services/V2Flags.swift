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
    /// Default OFF: V2 ships the designer's stylized map (fake pins at
    /// hardcoded positions) and does not render MapKit or query VenueStore.
    /// A user that taps a pin finds a mockup venue, not their real options.
    /// Flip to true only once the mockup "map" is backed by real venues.
    static var exploreV2: Bool   { read("bp_v2_explore_enabled",   default: false) }
    /// Tab 2 → SocialV2View in place of SocialView.
    /// Default OFF: V2 renders four fake friends (Mía/Jules/Dani/Val) and
    /// six fake stories as mockup literals; the real feed (FriendsTonightStore,
    /// stories, HostEvent) is not wired yet. V1 keeps real friends visible.
    static var socialV2: Bool    { read("bp_v2_social_enabled",    default: false) }
    /// Tab 3 → TripsListV2View in place of TripsListView.
    /// Default ON: V2 is wired to the real TripStore (my trips + discoverable
    /// + create + join by code + deep links). Safe to ship.
    static var tripsListV2: Bool { read("bp_v2_trips_enabled",     default: true) }
    /// Tap on a venue → VenuePulseView in place of VenueDetailView.
    /// Default OFF: V2 shows the real venue name/neighborhood but every
    /// dynamic detail (drinks, friends-inside, events, pulse %) is mockup.
    /// V1 renders the real menu, events, pass CTAs and media.
    static var venuePulseV2: Bool { read("bp_v2_venue_enabled",    default: false) }
    /// Login → AuthLoginV2View in place of NativeAuthView.
    /// NOT enabled by default — AuthV2 is pure visual, needs its real
    /// email/password/Apple handlers wired before it goes live.
    static var authV2: Bool      { read("bp_v2_auth_enabled",      default: false) }
    /// Priority Entry hub → PriorityEntryV2Container in place of PriorityEntryHubView.
    /// Default OFF: wired (real SkipLine / Table / Tickets destinations, outbox
    /// strip, model-derived prices) but V2 copy is Spanish-only while V1 is
    /// es/en/pt — owner decision pending.
    static var priorityV2: Bool  { read("bp_v2_priority_enabled",  default: false) }
    /// Skip the Line purchase → SkipTheLineV2Container (V2 skin over the V1
    /// payment machine: Apple Pay w/ idempotency keys, wallet, card via
    /// CardPaymentView, PassRegistrationOutbox) in place of SkipLinePassView.
    /// Default OFF until it has been exercised against Stripe test mode.
    static var skipLineV2: Bool  { read("bp_v2_skipline_enabled",  default: false) }
    /// Cart sheet → CartV2View (wired to CartStore + the same CardPaymentView /
    /// wallet / Apple Pay paths as CartView) in place of CartView.
    /// Default OFF until exercised against Stripe test mode.
    static var cartV2: Bool      { read("bp_v2_cart_enabled",      default: false) }
}
