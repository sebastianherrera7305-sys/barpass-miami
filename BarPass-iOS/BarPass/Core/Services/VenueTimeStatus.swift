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
    ///
    /// Hand-rolled on purpose. The previous version compiled an
    /// NSRegularExpression and allocated a DateFormatter, a Locale and a
    /// Calendar on every call. That is fine a few times a screen and fatal in
    /// a ranking pass: `VenueRanking.goingOutScore` calls this three times per
    /// venue, so one Tonight render over the full catalogue made ~5,400
    /// DateFormatters on the main thread and the app froze in build 63
    /// ("fui a salir y se quedó pegado", 2026-09-12). A character scan costs
    /// microseconds and allocates nothing.
    static func minutesSinceMidnight(_ raw: String) -> Int? {
        var hour = 0
        var minute = 0
        var sawColon = false
        var hourDigits = 0
        var minuteDigits = 0
        var isPM: Bool? = nil

        for ch in raw {
            switch ch {
            case "0"..."9":
                let digit = Int(ch.wholeNumberValue ?? -1)
                guard digit >= 0 else { return nil }
                if sawColon {
                    minuteDigits += 1
                    if minuteDigits > 2 { return nil }
                    minute = minute * 10 + digit
                } else {
                    hourDigits += 1
                    if hourDigits > 2 { return nil }
                    hour = hour * 10 + digit
                }
            case ":":
                if sawColon || hourDigits == 0 { return nil }
                sawColon = true
            case "a", "A":
                if isPM != nil { return nil }
                isPM = false
            case "p", "P":
                if isPM != nil { return nil }
                isPM = true
            // Separators and the "M" of AM/PM carry no information.
            case "m", "M", " ", ".", "\t":
                continue
            default:
                return nil
            }
        }

        guard sawColon, hourDigits > 0, minuteDigits == 2, minute < 60 else { return nil }

        if let isPM {
            // 12-hour clock: 12 AM is midnight, 12 PM is noon.
            guard (1...12).contains(hour) else { return nil }
            if hour == 12 { hour = 0 }
            if isPM { hour += 12 }
        } else {
            guard hour < 24 else { return nil }
        }
        return hour * 60 + minute
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
