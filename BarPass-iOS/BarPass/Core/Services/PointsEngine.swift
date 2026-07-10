import SwiftUI

// MARK: - XP actions

enum XPAction: String, Codable, CaseIterable {
    case checkIn      = "check_in"
    case leaveReview  = "leave_review"
    case shareVenue   = "share_venue"
    case createTrip   = "create_trip"
    case completeTrip = "complete_trip"
    case inviteFriend = "invite_friend"

    var xp: Int {
        switch self {
        case .checkIn:      return 50
        case .leaveReview:  return 75
        case .shareVenue:   return 25
        case .createTrip:   return 100
        case .completeTrip: return 200
        case .inviteFriend: return 200
        }
    }

    var label: String {
        switch self {
        case .checkIn:      return "Check-in"
        case .leaveReview:  return "Review"
        case .shareVenue:   return "Compartir"
        case .createTrip:   return "Trip creado"
        case .completeTrip: return "Trip completado"
        case .inviteFriend: return "Amigo invitado"
        }
    }
}

// MARK: - Engine

/// Dynamic XP: awards points for real actions, persists to UserDefaults,
/// and exposes level progression. Views observe it; non-view code awards
/// through `PointsEngine.shared`.
@MainActor
final class PointsEngine: ObservableObject {
    static let shared = PointsEngine()
    private static let key = "bp_points_state"

    @Published private(set) var totalXP: Int = 0
    @Published private(set) var checkinCount: Int = 0
    @Published private(set) var reviewCount: Int = 0
    @Published private(set) var shareCount: Int = 0
    @Published private(set) var tripCount: Int = 0
    /// Last award, for the toast ("+50 XP · Check-in"). Cleared by the UI.
    @Published var lastAward: (action: XPAction, xp: Int)?

    /// venue.id → yyyy-MM-dd of last check-in (prevents same-day farming).
    private var lastCheckins: [String: String] = [:]
    /// Venues already reviewed (one review award per venue).
    private var reviewedVenues: Set<String> = []

    private struct State: Codable {
        var totalXP: Int
        var checkinCount: Int
        var reviewCount: Int
        var shareCount: Int
        var tripCount: Int
        var lastCheckins: [String: String]
        var reviewedVenues: Set<String>?
    }

    private init() { load() }

    // MARK: Levels

    static let levels: [(name: String, floor: Int)] = [
        ("Newcomer", 0), ("Insider", 500), ("VIP", 2000), ("Elite", 5000), ("Icon", 10000),
    ]

    var levelIndex: Int {
        Self.levels.lastIndex { totalXP >= $0.floor } ?? 0
    }
    var levelName: String { Self.levels[levelIndex].name }
    var nextLevelName: String? {
        levelIndex + 1 < Self.levels.count ? Self.levels[levelIndex + 1].name : nil
    }
    var xpForCurrentLevel: Int { Self.levels[levelIndex].floor }
    var xpForNextLevel: Int? {
        levelIndex + 1 < Self.levels.count ? Self.levels[levelIndex + 1].floor : nil
    }
    /// 0…1 progress toward the next level (1 at max level).
    var progress: Double {
        guard let next = xpForNextLevel else { return 1 }
        let span = Double(next - xpForCurrentLevel)
        return span > 0 ? Double(totalXP - xpForCurrentLevel) / span : 1
    }

    // MARK: Awards

    @discardableResult
    func award(_ action: XPAction) -> Int {
        switch action {
        case .checkIn:      checkinCount += 1
        case .leaveReview:  reviewCount += 1
        case .shareVenue:   shareCount += 1
        case .createTrip, .completeTrip: tripCount += 1
        case .inviteFriend: break
        }
        totalXP += action.xp
        lastAward = (action, action.xp)
        BPAnalytics.track(.earnXP(action: action.rawValue, amount: action.xp))
        BPHaptics.success()
        save()
        return action.xp
    }

    /// Check-in with same-day-per-venue guard. Returns XP or nil if already
    /// checked in today.
    @discardableResult
    func checkIn(venueId: String) -> Int? {
        let today = Self.dayStamp()
        guard lastCheckins[venueId] != today else { return nil }
        lastCheckins[venueId] = today
        return award(.checkIn)
    }

    func hasCheckedInToday(venueId: String) -> Bool {
        lastCheckins[venueId] == Self.dayStamp()
    }

    /// One review award per venue.
    @discardableResult
    func leaveReview(venueId: String) -> Int? {
        guard !reviewedVenues.contains(venueId) else { return nil }
        reviewedVenues.insert(venueId)
        return award(.leaveReview)
    }

    func hasReviewed(venueId: String) -> Bool { reviewedVenues.contains(venueId) }

    func reset() {
        totalXP = 0; checkinCount = 0; reviewCount = 0; shareCount = 0; tripCount = 0
        lastCheckins = [:]; reviewedVenues = []; lastAward = nil
        save()
    }

    // MARK: Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let s = try? JSONDecoder().decode(State.self, from: data) else { return }
        totalXP = s.totalXP; checkinCount = s.checkinCount; reviewCount = s.reviewCount
        shareCount = s.shareCount; tripCount = s.tripCount; lastCheckins = s.lastCheckins
        reviewedVenues = s.reviewedVenues ?? []
    }

    private func save() {
        let s = State(totalXP: totalXP, checkinCount: checkinCount, reviewCount: reviewCount,
                      shareCount: shareCount, tripCount: tripCount, lastCheckins: lastCheckins,
                      reviewedVenues: reviewedVenues)
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    private static func dayStamp() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
