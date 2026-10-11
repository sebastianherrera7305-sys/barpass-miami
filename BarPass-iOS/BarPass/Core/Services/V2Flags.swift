import Foundation

/// Feature flags for the v17.1 UI redesign. Every V2 screen that replaces an
/// existing V1 screen is gated here so we can roll each one back
/// independently from a UserDefault without a release:
///
///   defaults write com.sebastian.barpass bp_v2_<name>_enabled -bool NO
///
/// All V2 screens were cabled to real data (commit 685bcb25), fixed per a
/// read-only review (9ca76fde), and verified by a second adversarial
/// review as flag-safe. Defaults flipped to true for Build 90: Build 89
/// shipped them OFF and the owner reported "same old desing" because every
/// screen fell through to V1. Any screen can still be force-disabled
/// per-device with the `defaults write` incantation above.
enum V2Flags {
    private static func read(_ key: String, default defaultValue: Bool) -> Bool {
        if UserDefaults.standard.object(forKey: key) == nil { return defaultValue }
        return UserDefaults.standard.bool(forKey: key)
    }

    /// Tab 1 → ExploreV2View in place of ExploreView.
    /// Cabled to real VenueStore (pins projected into city bbox from
    /// lat/lng), real search (name/neighborhood/type, diacritic-insensitive),
    /// list mode, FriendsTonightStore strip tapping to Social, real location
    /// dot via UserLocationProvider. Capability gaps vs V1 (stadiums,
    /// full search engine) are owner-level, not safety.
    static var exploreV2: Bool   { read("bp_v2_explore_enabled",   default: true) }
    /// Tab 2 → SocialV2View in place of SocialView.
    /// Real feed: FriendsTonightStore + VenueStoryPulseStore +
    /// HostEventRepository. "Acaba de llegar" only when <30min. Pills to
    /// FriendsListView / HostEventsListView. Lost UniversityListView door
    /// (owner-level).
    static var socialV2: Bool    { read("bp_v2_social_enabled",    default: true) }
    /// Tab 3 → TripsListV2View in place of TripsListView.
    /// Real TripStore (my trips + discoverable + create + join by code +
    /// deep links). First V2 that shipped ON.
    static var tripsListV2: Bool { read("bp_v2_trips_enabled",     default: true) }
    /// Tap on a venue → VenuePulseView in place of VenueDetailView.
    /// init(venue:) renders from BarPassVenue (name/neighborhood/closeTime/
    /// timezone/drinks). Real "friends inside" via FriendsTonightStore.
    /// Share wired to ShareManager + analytics + XP. Mockup sections
    /// (occupancy curve, voices, Remy take) hidden in Release.
    static var venuePulseV2: Bool { read("bp_v2_venue_enabled",    default: true) }
    /// Login → AuthLoginV2Container in place of NativeAuthView.
    /// AuthService.signIn/signUp/signInWithApple with SHA-256 nonce in the
    /// request. Session restore on launch. Guest mode preserved. Copy is
    /// Spanish-only until L10n keys land (owner-level).
    static var authV2: Bool      { read("bp_v2_auth_enabled",      default: true) }
    /// Priority Entry hub → PriorityEntryV2Container in place of
    /// PriorityEntryHubView. Routes to the real SkipLine/Table/Tickets
    /// destinations with analytics + priorityEvent branch + PassOutboxStrip.
    /// "Desde $" prices derived from the live models, not literals.
    static var priorityV2: Bool  { read("bp_v2_priority_enabled",  default: true) }
    /// Skip the Line purchase → SkipTheLineV2Container.
    /// V2 skin over the V1 payment machine, verbatim: Apple Pay with one
    /// idempotency key per (option, attempt-series), wallet via
    /// spendWallet, card via CardPaymentView + onOrderId bridge,
    /// PassRegistrationOutbox.register BEFORE presenting the pass, expiry
    /// reminder scheduled. Prices always from the model.
    static var skipLineV2: Bool  { read("bp_v2_skipline_enabled",  default: true) }
    /// Cart sheet → CartV2View.
    /// CartStore-driven items/totals. Same three pay paths as CartView
    /// line-for-line (wallet when balance >= total, otherwise top-up
    /// prompt; CardPaymentView; ApplePayService). handleOrderSuccess
    /// captures venueName BEFORE clear() so order confirmations keep the
    /// venue.
    static var cartV2: Bool      { read("bp_v2_cart_enabled",      default: true) }
}
