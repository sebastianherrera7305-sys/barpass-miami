import Foundation

/// Editorial curation, NOT a verified production data field — unlike every
/// other signal `ExperienceScorer` uses (rating, events, open-now, tags),
/// this list has no source in Supabase. It's a manually reviewed set of
/// venues genuinely known for a college/young-adult nightlife crowd in
/// Miami, cross-checked against each venue's real `business_status` and
/// `google_place_id` in production (all OPERATIONAL as of 2026-08-12) before
/// being added here. `KUSH Wynwood` was excluded from the original 22
/// candidates — Google's own data marks it `CLOSED_TEMPORARILY`.
///
/// Keyed by `slug` (stable, human-readable) rather than `id` (UUID) so this
/// list stays auditable/diffable without a database round trip.
enum CollegeNightlifeCuration {
    static let slugs: Set<String> = [
        "club-space",
        "e11even-miami",
        "liv-nightclub-miami",
        "mangos-south-beach",
        "amor-miami",
        "sugar-rooftop",
        "astra-miami-rooftop",
        "highbar-pool-bar-sky",
        "blue-martini",
        "macs-club-deuce",
        "the-clevelander-bar",
        "wet-willies",
        "kill-your-idol",
        "lagniappe",
        "sha-wynwood",
        "1-800-lucky",
        "coyo-taco",
        "sandbar-sports-grill",
        "montys-raw-bar",
        "bougainvilleas-old-florida-tavern",
        "the-bar",
    ]

    static func isCurated(_ venue: BarPassVenue) -> Bool {
        guard let slug = venue.slug else { return false }
        return slugs.contains(slug)
    }

    /// True on the real nights this crowd actually goes out — Thursday
    /// through Saturday. Not a per-venue claim (no "X is best on Fridays"
    /// hardcoding without evidence); just when the curated boost applies at
    /// all, using the calendar's real current weekday.
    static func isGoingOutNight(_ date: Date = Date()) -> Bool {
        let weekday = Calendar.current.component(.weekday, from: date)
        // Calendar.weekday: 1 = Sunday ... 5 = Thursday, 6 = Friday, 7 = Saturday
        return weekday == 5 || weekday == 6 || weekday == 7
    }
}
