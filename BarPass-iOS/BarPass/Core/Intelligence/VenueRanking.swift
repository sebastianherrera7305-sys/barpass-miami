import Foundation

/// How good a venue actually is, when some venues have 9 reviews and others
/// have 1,410.
///
/// TestFlight, 2026-09-12, asking for the best college bars in Gainesville:
/// "los que tenemos son una mierda". He was right, and the cause was the
/// sort, not the catalog. Ranking on the raw rating put Rush Nightclub
/// (5.0 from 9 reviews) above Loosey's (4.5 from 1,410) and a coffee shop
/// above every real bar in town. A 5.0 from 9 people is not evidence; it's
/// noise that happens to be at the top of a scale.
///
/// The fix is the standard one: pull each venue's rating toward the catalog
/// average in proportion to how little evidence it has. A venue needs real
/// volume before its rating is allowed to speak for itself. This is the same
/// weighting IMDb's top list uses, and it needs no data we don't already have.
enum VenueRanking {

    /// Reviews a venue needs before its own rating outweighs the prior.
    /// 150 is deliberately high for nightlife: a bar that only 30 people
    /// reviewed is a bar most people haven't been to.
    static let confidenceThreshold = 150.0

    /// The catalog's own average, not an invented constant. Passed in so a
    /// city's ranking is judged against the same catalog it belongs to.
    static func meanRating(of venues: [BarPassVenue]) -> Double {
        let rated = venues.compactMap { $0.reviewCount > 0 ? $0.rating : nil }
        guard !rated.isEmpty else { return 4.0 }
        return rated.reduce(0, +) / Double(rated.count)
    }

    /// Confidence-weighted rating. With no reviews it IS the catalog mean —
    /// an unrated venue is neither promoted nor buried, which is the honest
    /// position. With many reviews it converges on the venue's own rating.
    static func score(_ venue: BarPassVenue, mean: Double) -> Double {
        let n = Double(venue.reviewCount)
        guard n > 0 else { return mean }
        let weight = n / (n + confidenceThreshold)
        return weight * venue.rating + (1 - weight) * mean
    }

    /// Venues ordered by how confidently good they are. Trending still wins
    /// ties, as it did before, because that's a real-time signal rather than
    /// a historical one.
    static func ranked(_ venues: [BarPassVenue]) -> [BarPassVenue] {
        let mean = meanRating(of: venues)
        return venues
            .map { ($0, score($0, mean: mean)) }
            .sorted { a, b in
                if a.0.isTrending != b.0.isTrending { return a.0.isTrending }
                return a.1 > b.1
            }
            .map(\.0)
    }

    // MARK: - Where the night actually is

    /// Ranking for "I'm out right now, where do I go".
    ///
    /// TestFlight, 2026-09-12, after a night in Gainesville: "vine y no
    /// encontré nada para ir a rumbear". The venues were all in the catalog —
    /// MacDinton's, Salty Dog, Balls, University Club, 16 of them open past
    /// 1 AM. The list just never showed them, because it sorted on rating,
    /// and rating answers "is this place good", not "is this where the night
    /// is". A 4.9 coffee shop closing at 6 PM outranked the college bar with
    /// 1,204 reviews that closes at 2 AM.
    ///
    /// So this scores the things that actually decide where you go at 11 PM:
    /// is it still open when you'd arrive, is it a place people go out to,
    /// and do a lot of people actually go. Rating is a tiebreaker here, not
    /// the axis.
    static func goingOutScore(_ venue: BarPassVenue, at date: Date = Date(), mean: Double) -> Double {
        var score = 0.0

        // Still open an hour from now — you're deciding where to head, not
        // where you already are. A place that closes before you arrive is
        // worth nothing regardless of how good it is.
        let cal = Calendar.current
        let soon = cal.date(byAdding: .hour, value: 1, to: date) ?? date
        let minute = cal.component(.hour, from: soon) * 60 + cal.component(.minute, from: soon)
        guard venue.isOpenAt(minutesSinceMidnight: minute) else { return 0 }

        // How late it goes is the single strongest signal of what kind of
        // night a place is for. A 2 AM close is a going-out venue; a 10 PM
        // close is dinner.
        if let closeMinutes = Self.minutes(venue.closeTime) {
            // Closing times past midnight read as small numbers; treat them
            // as late, which is what they are.
            let lateness = closeMinutes < 8 * 60 ? closeMinutes + 24 * 60 : closeMinutes
            if lateness >= 26 * 60 { score += 30 }        // 2 AM or later
            else if lateness >= 25 * 60 { score += 22 }   // 1 AM
            else if lateness >= 24 * 60 { score += 14 }   // midnight
            else if lateness >= 23 * 60 { score += 6 }    // 11 PM
        }

        // What kind of place it is.
        switch venue.type {
        case .club:      score += 18
        case .bar:       score += 15
        case .lounge:    score += 10
        case .rooftop:   score += 10
        case .brewery:   score += 6
        case .sportsBar: score += 6
        case .restaurant: score += 0
        }

        // Popularity, not opinion: how many people actually go. Logarithmic —
        // the gap between 50 and 500 reviews matters, between 3,000 and 3,500
        // doesn't. Capped so one enormous chain restaurant can't dominate.
        let reviews = Double(max(venue.reviewCount, 0))
        score += min(log10(reviews + 1) * 6, 20)

        // Quality as a tiebreaker, confidence-weighted so a 5.0 from nine
        // people can't jump the queue.
        score += (Self.score(venue, mean: mean) - mean) * 4

        if venue.isTrending { score += 8 }
        return score
    }

    /// The going-out list. Venues that are closed (or about to be) drop out
    /// entirely rather than ranking last — showing a closed bar as an option
    /// is worse than showing nothing.
    static func goingOutNow(_ venues: [BarPassVenue], at date: Date = Date(), limit: Int = 20) -> [BarPassVenue] {
        let mean = meanRating(of: venues)
        return venues
            .map { ($0, goingOutScore($0, at: date, mean: mean)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    /// A venue's opening hours, in the words the card would use — "Open until
    /// 2:00 AM" — for the lists ranked by `goingOutScore`. It states the one
    /// signal that actually decided the order (how late the place goes, then
    /// how many people go), never a reason belonging to a different scorer.
    /// Returns nil rather than inventing a reason when the venue has none of
    /// these facts on record.
    static func goingOutReason(_ venue: BarPassVenue) -> String? {
        if let closeMinutes = minutes(venue.closeTime) {
            let lateness = closeMinutes < 8 * 60 ? closeMinutes + 24 * 60 : closeMinutes
            if lateness >= 24 * 60 {
                return String(format: L10n.tSync("plan.badge.openUntil"), venue.closeTime)
            }
        }
        if venue.reviewCount > 5000 {
            if let city = venue.city, !city.isEmpty {
                return String(format: L10n.tSync("reason.cityFavorite"), city, venue.reviewCount.formatted())
            }
            return String(format: L10n.tSync("reason.localFavorite"), venue.reviewCount.formatted())
        }
        if venue.hasHappyHour, let until = venue.happyHourUntil {
            return String(format: L10n.tSync("reason.happyHour"), until)
        }
        if venue.isTrending { return L10n.tSync("reason.trending") }
        return nil
    }

    /// Minutes since midnight, via `VenueTimeStatus` — the app's single source
    /// of truth for venue clock strings.
    ///
    /// This used to parse 24h "HH:MM" only, which silently disabled the entire
    /// going-out ranking on real data: `SupabaseVenueRepository` runs every
    /// venue's hours through `formatTime24to12`, so what actually arrives here
    /// is "2:00 AM" / "11:00 PM". `Int("00 AM")` is nil, so every venue looked
    /// like it had unknown hours — no lateness bonus for anyone, and the
    /// "closed, drop it" filter never fired. Only the `.preview` fixtures,
    /// which are 12h too, and hand-written 24h strings ever reached it.
    private static func minutes(_ time: String?) -> Int? {
        guard let time else { return nil }
        return VenueTimeStatus.minutesSinceMidnight(time)
    }
}

extension BarPassVenue {
    /// Open at a given minute-of-day, handling closing times past midnight
    /// ("11:00 PM"–"2:00 AM"). Unknown or unparseable hours count as open, so
    /// a data gap never silently hides a venue.
    ///
    /// Parsing goes through `VenueTimeStatus`, which reads both the 24h
    /// "22:00" form and the 12h "2:00 AM" form the repository actually
    /// produces. The local parser this replaced only understood 24h, so on
    /// real data every venue fell into the "unknown hours" branch and counted
    /// as open around the clock — the lenient fallback was doing all the work
    /// and the check itself was dead.
    func isOpenAt(minutesSinceMidnight now: Int) -> Bool {
        func mins(_ s: String) -> Int? { VenueTimeStatus.minutesSinceMidnight(s) }
        guard let open = mins(openTime), let close = mins(closeTime), open != close else { return true }
        return close > open ? (now >= open && now < close) : (now >= open || now < close)
    }
}
