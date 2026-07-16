import Foundation

// MARK: - AI night plan (Plan tab)

struct PlanStop: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    let time: String
    let venueName: String
    let venueNeighborhood: String
    let venuePriceRange: String
    let note: String
}

struct NightPlan: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var title: String = "Mi plan de noche"
    var stops: [PlanStop] = []
    var totalEst: String = ""
    var aiInsight: String = ""
    var createdAt: Date = .now

    /// Deterministic sample plan built from real venues (no invented spots):
    /// warm-up (happy hour / rooftop) → mid (lounge/bar) → peak (club).
    static func sample(for prompt: String, venues: [BarPassVenue]) -> NightPlan {
        let sorted = venues.sorted { $0.rating > $1.rating }
        let warm = sorted.first { $0.hasHappyHour || $0.type == .rooftop || $0.type == .restaurant }
        let mid  = sorted.first { ($0.type == .lounge || $0.type == .bar) && $0.id != warm?.id }
        let peak = sorted.first { $0.type == .club && $0.id != warm?.id && $0.id != mid?.id }

        let picks = [warm, mid, peak].compactMap { $0 }
        let times = ["8:00 PM", "10:30 PM", "12:30 AM"]
        // Notes/insight are l10n keys resolved at the view via L10n.shared.t(...).
        let notes = [
            "nightplan.warmup",
            "nightplan.mid",
            "nightplan.peak",
        ]

        let stops = picks.enumerated().map { i, v in
            PlanStop(
                time: times[min(i, times.count - 1)],
                venueName: v.name,
                venueNeighborhood: v.neighborhood,
                venuePriceRange: v.priceRange,
                note: notes[min(i, notes.count - 1)]
            )
        }

        // Key resolved at the view. "nightplan.insight" takes the first stop's
        // venue name as %@; the fallback key has no placeholder.
        let insight = picks.first != nil ? "nightplan.insight" : "nightplan.insight.fallback"

        return NightPlan(
            title: prompt.isEmpty ? "Mi plan de noche" : prompt,
            stops: stops,
            totalEst: "$80–150 / persona",
            aiInsight: insight
        )
    }
}
