import Foundation

/// What kind of venue makes sense to suggest right now, based purely on the
/// clock — never on a venue's own hours (those come from real `open_time`/
/// `close_time` via `VenueTimeStatus`, which already refuses to guess when a
/// value can't be parsed). This is a UX weighting heuristic, not a claim
/// about any specific venue's real schedule.
enum DayPart {
    case afternoon    // 12:00–17:00
    case earlyEvening // 17:00–20:00
    case night        // 20:00–02:00
    case lateNight    // 02:00–05:00
    case morning      // 05:00–12:00 — nightlife isn't relevant; no type gets boosted

    static func current(_ date: Date = Date()) -> DayPart {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 12..<17: return .afternoon
        case 17..<20: return .earlyEvening
        case 20..<24, 0..<2: return .night
        case 2..<5: return .lateNight
        default: return .morning
        }
    }

    /// Venue types that make sense to suggest during this part of the day.
    /// Empty set = no daypart-based boost applies (`.morning`) rather than
    /// guessing something is relevant.
    var preferredTypes: Set<VenueType> {
        switch self {
        case .afternoon:    return [.restaurant, .rooftop, .brewery]
        case .earlyEvening: return [.restaurant, .lounge, .rooftop]
        case .night:        return [.club, .bar, .lounge, .sportsBar]
        case .lateNight:    return [.club, .bar]
        case .morning:      return []
        }
    }
}
