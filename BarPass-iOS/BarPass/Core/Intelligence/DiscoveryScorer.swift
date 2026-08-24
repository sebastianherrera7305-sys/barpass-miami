import Foundation

/// Explore's ranking, deliberately separate from `ExperienceScorer` — Tonight
/// answers "where should I go right now" (time of day, live events,
/// curation, personalization); Explore answers "what's out there worth
/// discovering" (objective quality only). No clock, no event window, no
/// curation list, no favorites — reusing `ExperienceScorer` here would make
/// Explore just a slower, more confusing copy of Tonight.
enum DiscoveryScorer {
    static func score(_ v: BarPassVenue) -> Double {
        v.rating + min(Double(v.reviewCount) / 5_000.0, 1.0)
    }
}
