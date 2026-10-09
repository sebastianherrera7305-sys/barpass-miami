import Foundation
import os

// MARK: - AnalyticsEvent

enum AnalyticsEvent {
    case signIn(method: String, duration: Double)
    case signUp(method: String, duration: Double)
    case forgotPassword
    case sessionRestored

    case viewScreen(String)
    case viewVenue(String)
    case viewTrip(String)
    case viewPlan

    case createTrip
    case createPlan(method: String)
    case savePlan

    case startPayment(method: String, amount: Double)
    case paymentSuccess(method: String, amount: Double)
    case paymentFailed(method: String, error: String)

    case addToCart(item: String, venue: String)
    case cartCheckout(itemCount: Int, total: Double)

    case buySkipLinePass(venue: String)
    case buyTableReservation(venue: String)
    case buyEventTicket(venue: String, event: String)

    case openMaps(venue: String)
    case shareVenue(venue: String)
    case deepLink(URL)

    case earnXP(action: String, amount: Int)

    case error(name: String, details: String?)
    case warning(name: String, details: String?)

    // M4 — minimum set the master directive asked for. Properties kept
    // narrow deliberately — no lat/lng, no raw friend ids, no PII. See
    // docs/analytics-events.md for the shipping contract.
    /// Cold vs warm start, time since the previous foreground.
    case appOpened(coldStart: Bool, secondsSinceLastOpen: Int?)
    /// User saved their illustrated avatar for the first (or Nth) time.
    case avatarSaved(isFirstTime: Bool)
    /// Opened the Friends / Social Graph surface.
    case socialGraphViewed
    /// Opened a friend's profile from the graph.
    case friendProfileOpened(friendIdHash: String)
    /// Accepted or completed a friend relationship. source = search / qr / contacts / suggestion.
    case friendAdded(source: String)
    /// A trip created from the AI prompt vs the manual wizard, with its initial member count.
    case tripCreatedDetailed(method: String, memberCount: Int)
    /// User joined an existing trip; source = invite_link / code / request_accepted.
    case tripJoined(tripId: String, source: String)
    /// Trip was closed server-side (complete_trip RPC succeeded).
    case tripCompleted(tripId: String, stopCount: Int, durationHours: Double?)
    /// A user physically checked into a venue (venue_id only — never GPS).
    case venueCheckin(venueId: String, tripId: String?)
}

// MARK: - AnalyticsService Protocol

protocol AnalyticsService: Sendable {
    func track(_ event: AnalyticsEvent)
    func setUserID(_ id: String?)
    func flush()
}

// MARK: - Console Analytics (debug)

final class ConsoleAnalyticsService: AnalyticsService {
    private let log = OSLog(subsystem: "io.barpass", category: "Analytics")

    func track(_ event: AnalyticsEvent) {
        #if DEBUG
        let emoji: String
        let label: String
        switch event {
        case .signIn:              (emoji, label) = ("🔑", "signIn")
        case .signUp:              (emoji, label) = ("📝", "signUp")
        case .forgotPassword:      (emoji, label) = ("🔐", "forgotPassword")
        case .sessionRestored:     (emoji, label) = ("🔄", "sessionRestored")
        case .viewScreen:          (emoji, label) = ("📱", "viewScreen")
        case .viewVenue:           (emoji, label) = ("🏠", "viewVenue")
        case .viewTrip:            (emoji, label) = ("🧳", "viewTrip")
        case .viewPlan:            (emoji, label) = ("📋", "viewPlan")
        case .createTrip:          (emoji, label) = ("✨", "createTrip")
        case .createPlan:          (emoji, label) = ("🌟", "createPlan")
        case .savePlan:            (emoji, label) = ("💾", "savePlan")
        case .startPayment:        (emoji, label) = ("💳", "startPayment")
        case .paymentSuccess:      (emoji, label) = ("✅", "paymentSuccess")
        case .paymentFailed:       (emoji, label) = ("❌", "paymentFailed")
        case .addToCart:           (emoji, label) = ("🛒", "addToCart")
        case .cartCheckout:        (emoji, label) = ("🧾", "cartCheckout")
        case .buySkipLinePass:     (emoji, label) = ("⚡", "buySkipLinePass")
        case .buyTableReservation: (emoji, label) = ("🪑", "buyTableReservation")
        case .buyEventTicket:      (emoji, label) = ("🎫", "buyEventTicket")
        case .openMaps:            (emoji, label) = ("🗺️", "openMaps")
        case .shareVenue:          (emoji, label) = ("📤", "shareVenue")
        case .deepLink:            (emoji, label) = ("🔗", "deepLink")
        case .earnXP:              (emoji, label) = ("🏆", "earnXP")
        case .error:               (emoji, label) = ("🚨", "error")
        case .warning:             (emoji, label) = ("⚠️", "warning")
        case .appOpened:           (emoji, label) = ("🚀", "appOpened")
        case .avatarSaved:         (emoji, label) = ("🎭", "avatarSaved")
        case .socialGraphViewed:   (emoji, label) = ("👥", "socialGraphViewed")
        case .friendProfileOpened: (emoji, label) = ("👤", "friendProfileOpened")
        case .friendAdded:         (emoji, label) = ("🤝", "friendAdded")
        case .tripCreatedDetailed: (emoji, label) = ("✨", "tripCreated")
        case .tripJoined:          (emoji, label) = ("🧳", "tripJoined")
        case .tripCompleted:       (emoji, label) = ("🏁", "tripCompleted")
        case .venueCheckin:        (emoji, label) = ("📍", "venueCheckin")
        }
        os_log("[Analytics] %@ %@", log: log, type: .debug, emoji, label)
        #endif
    }

    func setUserID(_ id: String?) {
        #if DEBUG
        os_log("[Analytics] setUserID: %@", log: log, type: .debug, id ?? "nil")
        #endif
    }

    func flush() {}
}

// MARK: - Global entry point

enum BPAnalytics {
    nonisolated(unsafe) static var service: AnalyticsService = ConsoleAnalyticsService()

    static func track(_ event: AnalyticsEvent) {
        service.track(event)
    }

    static func setUserID(_ id: String?) {
        service.setUserID(id)
    }

    static func flush() {
        service.flush()
    }

    // Convenience for screen views
    static func screen(_ name: String) {
        track(.viewScreen(name))
    }
}
