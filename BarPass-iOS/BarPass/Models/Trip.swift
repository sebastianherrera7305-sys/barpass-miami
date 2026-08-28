import Foundation

// MARK: - Trip domain models

enum TripVisibility: String, Codable, CaseIterable {
    case privateTrip = "private"
    case semiOpen    = "semi_open"
    case publicTrip  = "public"

    var label: String {
        switch self {
        case .privateTrip: return L10n.shared.t("trip.visibility.private")
        case .semiOpen:    return L10n.shared.t("trip.visibility.semiOpen")
        case .publicTrip:  return L10n.shared.t("trip.visibility.public")
        }
    }
}

enum TripStatus: String, Codable {
    case planning, active, completed
}

enum StopType: String, Codable {
    case venue, event, game
}

enum StopVisibility: String, Codable {
    case tripOnly = "trip_only"
    case joinable
}

enum MemberRole: String, Codable {
    case organizer, coOrganizer, member
}

struct Stop: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var tripId: String
    var type: StopType = .venue
    var refId: String            // venue_id / event_id
    var venueName: String        // denormalized for display
    var emoji: String = "🍸"
    var date: Date
    var startTime: String = ""
    var endTime: String = ""
    var visibility: StopVisibility = .tripOnly
    var joinedUserIds: [String] = []
    var pendingStopRequests: [String] = []
}

extension Stop {
    /// Builds a sequenced itinerary from picked venues, anchored to each
    /// venue's actual opening time so a stop is never suggested before the
    /// venue is even open — previously both call sites (`TripsListView` and
    /// `TripCreateFlow`) fabricated times with plain arithmetic
    /// (`"\(7 + i*2):00 PM"`), unrelated to any real venue data.
    static func sequence(for venues: [BarPassVenue], tripId: String, date: Date) -> [Stop] {
        let ordered = venues.sorted { NightPlanner.phase(of: $0) < NightPlanner.phase(of: $1) }
        // Typical slot per phase, in minutes-since-midnight (peak wraps past
        // midnight into the next day).
        let phaseBaseline: [Int: Int] = [0: 20 * 60, 1: 22 * 60 + 30, 2: 24 * 60 + 30]

        var cursor = 0
        return ordered.map { v in
            let phase = NightPlanner.phase(of: v)
            let baseline = phaseBaseline[phase] ?? (20 * 60)
            // Very-early-morning open times (e.g. an after-hours spot open
            // "4:00 AM") mean "later tonight", not "earlier today" — push
            // past midnight for comparison purposes.
            let venueOpen = VenueTimeStatus.minutesSinceMidnight(v.openTime).map { $0 < 6 * 60 ? $0 + 24 * 60 : $0 }
            let start = max(baseline, venueOpen ?? baseline, cursor)
            let end = start + 120
            cursor = start + 120

            return Stop(
                tripId: tripId,
                refId: v.id,
                venueName: v.name,
                emoji: v.emoji,
                date: date,
                startTime: Self.formatMinutes(start),
                endTime: Self.formatMinutes(end)
            )
        }
    }

    private static func formatMinutes(_ totalMinutes: Int) -> String {
        let normalized = ((totalMinutes % (24 * 60)) + 24 * 60) % (24 * 60)
        var comps = DateComponents()
        comps.hour = normalized / 60
        comps.minute = normalized % 60
        guard let date = Calendar.current.date(from: comps) else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

struct Trip: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var creatorId: String
    var title: String
    var destinationCity: String
    var startDate: Date
    var endDate: Date
    var coverImage: String?
    var visibility: TripVisibility = .privateTrip
    var status: TripStatus = .planning
    var memberIds: [String] = []
    var pendingRequests: [String] = []
    var stops: [Stop] = []
    // Optional (not `= []`) so existing locally-persisted trips predating
    // these fields decode cleanly — synthesized Decodable only auto-fills
    // missing keys for Optional properties, not non-optional ones with a
    // default value.
    var coOrganizerIds: [String]? = nil
    var inviteCode: String? = nil

    func role(of userId: String) -> MemberRole {
        if userId == creatorId { return .organizer }
        if coOrganizerIds?.contains(userId) == true { return .coOrganizer }
        return .member
    }

    var stopsByDay: [(day: Date, stops: [Stop])] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: stops) { cal.startOfDay(for: $0.date) }
        return groups.keys.sorted().map { day in
            (day, groups[day]!.sorted { lhs, rhs in
                // Parse real clock times ("9:00 PM") for ordering — plain
                // string comparison sorted "10:00 PM" before "9:00 PM".
                let l = VenueTimeStatus.minutesSinceMidnight(lhs.startTime)
                let r = VenueTimeStatus.minutesSinceMidnight(rhs.startTime)
                if let l, let r, l != r { return l < r }
                if l != nil && r == nil { return true }
                if l == nil && r != nil { return false }
                return lhs.startTime < rhs.startTime
            })
        }
    }
}

// MARK: - Ratings & reputation

struct TripRating: Identifiable, Codable {
    var id: String = UUID().uuidString
    var scopeId: String          // trip_id or stop_id
    var raterId: String
    var rateeId: String
    var score: Int               // 1–5
    var tags: [String] = []
    var visible: Bool = false    // hidden until both sides rate
    var createdAt: Date = .now
}

enum ReputationBadge: String, Codable {
    case new, trustedPlanner = "trusted_planner", verified
}

struct UserReputation: Codable {
    var userId: String
    var badge: ReputationBadge = .new
    var completedTripsCount: Int = 0
    var avgScore: Double = 0
    var minThreshold: Int = 3

    /// avg_score is only public once enough trips are completed.
    var publicScore: Double? {
        completedTripsCount >= minThreshold ? avgScore : nil
    }
}


