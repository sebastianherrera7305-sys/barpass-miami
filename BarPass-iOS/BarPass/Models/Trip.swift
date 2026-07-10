import Foundation

// MARK: - Trip domain models

enum TripVisibility: String, Codable, CaseIterable {
    case privateTrip = "private"
    case semiOpen    = "semi_open"
    case publicTrip  = "public"

    var label: String {
        switch self {
        case .privateTrip: return "Privado"
        case .semiOpen:    return "Semi-abierto"
        case .publicTrip:  return "Público"
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

    var stopsByDay: [(day: Date, stops: [Stop])] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: stops) { cal.startOfDay(for: $0.date) }
        return groups.keys.sorted().map { day in
            (day, groups[day]!.sorted { $0.startTime < $1.startTime })
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


