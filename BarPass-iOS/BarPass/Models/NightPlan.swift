import Foundation
import CoreLocation

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

    /// Real-time-aware plan: answers "where should I go right now" instead
    /// of assuming a fixed 8pm→10:30pm→12:30am evening progression. Every
    /// stop is picked and labeled from the venue's *actual* current status
    /// (live event / starting soon / open now / later tonight), never a
    /// hardcoded clock time, and closed venues with nothing happening are
    /// excluded entirely. Falls back to tomorrow's top picks — clearly
    /// labeled as such — only when literally nothing is active right now,
    /// so the feed is never empty.
    ///
    /// Runs on MainActor because it resolves l10n keys directly (badges
    /// need formatted values baked in, e.g. "Starts in 20 min") — the sole
    /// call site (`PlanView.generatePlan`) already invokes this inside
    /// `MainActor.run`.
    ///
    /// - Parameter userLocation: last known device coordinate, if location
    ///   permission was granted. When present, closer open venues/events
    ///   rank higher within their tier (never overriding the live/soon/open
    ///   priority order — just breaking ties among otherwise-equal picks).
    ///   When nil (permission denied, unavailable, or not yet requested),
    ///   distance is simply omitted from scoring — BarPass is single-market
    ///   (Miami) today, so there's no separate "default market" to fall back
    ///   to beyond the existing rating/trending signal.
    @MainActor
    static func sample(for prompt: String, venues: [BarPassVenue], userLocation: CLLocationCoordinate2D? = nil) -> NightPlan {
        let now = Date()
        let l10n = L10n.shared

        let promptKeys = Set(
            prompt.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count > 3 }
        )
        func haystack(_ v: BarPassVenue) -> String {
            ([v.type.rawValue, v.name, v.neighborhood] + v.vibes + v.tags + v.musicGenres.map(\.rawValue))
                .joined(separator: " ").lowercased()
        }
        func promptScore(_ v: BarPassVenue) -> Double {
            promptKeys.isEmpty ? 0 : Double(promptKeys.filter { haystack(v).contains($0) }.count)
        }
        // Distance bonus decays to 0 by ~20km (covers metro Miami) — a tie
        // breaker, not a hard filter, so it never buries a livelier stop
        // further away in favor of a dead one nearby.
        func distanceBonus(_ v: BarPassVenue) -> Double {
            guard let userLocation else { return 0 }
            let userLoc = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
            let venueLoc = CLLocation(latitude: v.latitude, longitude: v.longitude)
            let km = userLoc.distance(from: venueLoc) / 1000
            return max(0, 1 - km / 20) * 0.5
        }
        func popularity(_ v: BarPassVenue) -> Double {
            (v.isTrending ? 1 : 0) + v.rating * 0.2 + min(Double(v.reviewCount) / 10_000, 0.5)
                + promptScore(v) * 2 + distanceBonus(v)
        }

        struct Candidate { let venue: BarPassVenue; let tier: Int; let rankScore: Double; let time: String; let noteKey: String }
        var candidates: [Candidate] = []

        for v in venues {
            // Best (soonest-relevant, not-yet-finished) event at this venue, if any.
            let bestEvent = v.upcomingEvents
                .map { (event: $0, status: VenueTimeStatus.status(for: $0, now: now)) }
                .filter { $0.status.isVisible }
                .min { lhs, rhs in
                    let (lt, rt) = (eventTierRank(lhs.status), eventTierRank(rhs.status))
                    return lt != rt ? lt < rt : lhs.event.date < rhs.event.date
                }

            if let best = bestEvent {
                let tier: Int; let time: String; let noteKey: String
                switch best.status {
                case .liveNow:
                    tier = 0; time = l10n.t("plan.badge.live"); noteKey = "plan.note.liveEvent"
                case .endingSoon(let mins):
                    tier = 0; time = String(format: l10n.t("plan.badge.endingSoon"), max(mins, 1)); noteKey = "plan.note.liveEvent"
                case .upcoming(let mins) where mins <= 60:
                    tier = 1; time = String(format: l10n.t("plan.badge.startsInMin"), mins); noteKey = "plan.note.startingSoon"
                case .upcoming(let mins):
                    tier = 3; time = String(format: l10n.t("plan.badge.startsInMin"), mins); noteKey = "plan.note.startingSoon"
                case .finished:
                    continue // unreachable (filtered by isVisible above), but exhaustive
                }
                candidates.append(Candidate(venue: v, tier: tier, rankScore: popularity(v), time: time, noteKey: noteKey))
            } else if v.isOpenNow {
                let closeMins = VenueTimeStatus.minutesUntilClose(openTime: v.openTime, closeTime: v.closeTime, now: now)
                let closingSoon = (closeMins ?? .max) <= 45
                candidates.append(Candidate(
                    venue: v, tier: 2,
                    rankScore: popularity(v) + (v.hasHappyHour ? 0.5 : 0),
                    time: closingSoon ? l10n.t("plan.badge.closingSoon") : String(format: l10n.t("plan.badge.openUntil"), v.closeTime),
                    noteKey: "plan.note.openNow"
                ))
            }
            // Closed venue with nothing happening — excluded, not recommended.
        }

        var ranked = candidates.sorted { $0.tier != $1.tier ? $0.tier < $1.tier : $0.rankScore > $1.rankScore }
        var isFallback = false

        if ranked.isEmpty {
            // Nothing open or active anywhere — recommend tomorrow's top
            // picks instead of leaving the feed blank, clearly labeled.
            isFallback = true
            ranked = venues
                .sorted { popularity($0) > popularity($1) }
                .prefix(4)
                .map { Candidate(venue: $0, tier: 4, rankScore: popularity($0), time: l10n.t("plan.badge.tomorrow"), noteKey: "plan.note.tomorrow") }
        }

        let picks = Array(ranked.prefix(4))
        let stops = picks.map { c in
            PlanStop(
                time: c.time,
                venueName: c.venue.name,
                venueNeighborhood: c.venue.neighborhood,
                venuePriceRange: c.venue.priceTier.symbol ?? l10n.t("venue.crowd.na"),
                note: c.noteKey
            )
        }

        return NightPlan(
            title: prompt.isEmpty ? "Mi plan de noche" : prompt,
            stops: stops,
            totalEst: "$80–150 / persona",
            aiInsight: isFallback ? "plan.insight.emptyFallback" : "plan.insight.live"
        )
    }

    /// Priority order for picking the single most relevant event at a venue:
    /// live/ending-soon beats starting-imminently beats further-out upcoming.
    private static func eventTierRank(_ status: VenueTimeStatus.EventStatus) -> Int {
        switch status {
        case .liveNow, .endingSoon:       return 0
        case .upcoming(let mins):         return mins <= 60 ? 1 : 2
        case .finished:                   return 3
        }
    }
}
