import Foundation

/// Single source of truth for "is this venue open right now" and "what's the
/// status of this event right now". Replaces two inconsistent ad-hoc
/// heuristics that used to live separately: `SupabaseVenueRepository`'s
/// open/close parsing (24h "HH:mm" only, correct overnight-wrap handling)
/// and the `-6h/+30h` (NightPlanner) vs `-6h/+36h` (TonightView) fuzzy event
/// windows, which disagreed with each other and never treated an event as
/// truly "finished".
enum VenueTimeStatus {

    /// Parses "11:00 PM" / "5:00 AM" / "23:00" style strings into minutes
    /// since midnight (24h). Returns nil if unparseable.
    static func minutesSinceMidnight(_ raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces).uppercased()
        guard !trimmed.isEmpty else { return nil }

        // 24h "HH:mm"
        if trimmed.range(of: #"^\d{1,2}:\d{2}$"#, options: .regularExpression) != nil {
            let parts = trimmed.split(separator: ":")
            guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
                  (0..<24).contains(h), (0..<60).contains(m) else { return nil }
            return h * 60 + m
        }

        // 12h "H:mm AM/PM"
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        let cleaned = trimmed.replacingOccurrences(of: ".", with: "")
        guard let date = formatter.date(from: cleaned) else { return nil }
        let comps = Calendar(identifier: .gregorian).dateComponents([.hour, .minute], from: date)
        guard let h = comps.hour, let m = comps.minute else { return nil }
        return h * 60 + m
    }

    /// True if `now` falls within [openTime, closeTime), correctly handling
    /// overnight ranges (e.g. open 11:00 PM, close 5:00 AM).
    static func isOpenNow(openTime: String, closeTime: String, now: Date = Date()) -> Bool {
        guard let openMin = minutesSinceMidnight(openTime),
              let closeMin = minutesSinceMidnight(closeTime) else { return false }
        let nowMin = minutesSinceMidnight(now)
        if openMin <= closeMin {
            return nowMin >= openMin && nowMin < closeMin
        } else {
            return nowMin >= openMin || nowMin < closeMin
        }
    }

    /// Minutes until close, assuming the venue is currently open (handles
    /// overnight wrap). Nil if not open or unparseable.
    static func minutesUntilClose(openTime: String, closeTime: String, now: Date = Date()) -> Int? {
        guard isOpenNow(openTime: openTime, closeTime: closeTime, now: now),
              let closeMin = minutesSinceMidnight(closeTime) else { return nil }
        let nowMin = minutesSinceMidnight(now)
        return closeMin > nowMin ? closeMin - nowMin : (24 * 60 - nowMin) + closeMin
    }

    private static func minutesSinceMidnight(_ date: Date) -> Int {
        let cal = Calendar.current
        return cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
    }

    /// No end-time is modeled on `VenueEvent` (only a start `date`) — this is
    /// the one assumed duration used everywhere an event needs a "still
    /// going?" answer. 4h covers typical club/show run times without
    /// keeping stale events alive indefinitely.
    static let defaultEventDuration: TimeInterval = 4 * 3600

    /// "Ending soon" kicks in inside this many minutes of the assumed end.
    static let endingSoonThreshold = 30

    enum EventStatus: Equatable {
        case upcoming(startsInMinutes: Int)
        case liveNow
        case endingSoon(endsInMinutes: Int)
        case finished

        var isVisible: Bool { self != .finished }
    }

    /// Classifies an event's status relative to `now`. Prefers the event's
    /// real `endDate` when the source actually provided one; only falls
    /// back to the fixed `duration` assumption when it's nil.
    static func status(for event: VenueEvent, now: Date = Date(), duration: TimeInterval = defaultEventDuration) -> EventStatus {
        let start = event.date
        let end = event.endDate ?? start.addingTimeInterval(duration)
        if now < start {
            return .upcoming(startsInMinutes: Int(start.timeIntervalSince(now) / 60))
        }
        if now >= end {
            return .finished
        }
        let minsLeft = Int(end.timeIntervalSince(now) / 60)
        return minsLeft <= endingSoonThreshold ? .endingSoon(endsInMinutes: minsLeft) : .liveNow
    }
}
