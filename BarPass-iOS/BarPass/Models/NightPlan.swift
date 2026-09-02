import Foundation
import CoreLocation

// MARK: - AI night plan (Plan tab)
//
// Canonical schema, unified 2026-09-01 (see CLAUDE.md → "Plan Consolidation
// Roadmap") with the one the AI concierge (`APIClient.fetchConciergePlan`,
// `barpass-v2/src/features/ai/services/plan-schema.ts`) already produces —
// `venueSlug` links back to a real venue, `estimatedSpend`/`totalEstimate`
// are numeric. `public.night_plans.plan` is jsonb, so this shape change
// needs no SQL migration; it just starts writing the new fields.

struct PlanStop: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    let time: String
    let venueSlug: String
    let venueName: String
    let note: String
    let estimatedSpend: Double
}

struct NightPlan: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var title: String
    var summary: String = ""
    var stops: [PlanStop] = []
    var totalEstimate: Double = 0
    var insiderTip: String = ""
    var createdAt: Date = .now

    /// Local, deterministic fallback used whenever the AI concierge is
    /// unavailable (missing server key, rate limited, offline) — Plan
    /// always tries the concierge first and only calls this on failure, so
    /// the user is never blocked on `NVIDIA_API_KEY` being configured.
    ///
    /// This is also where the old Trips "Prompt Your Night" flow's
    /// functionality landed after consolidation: vibe chips, company type
    /// and inclusive prefs (now merged into `PlanView`) feed `context` here
    /// and are scored via `ExperienceScorer` — the same engine Trips used —
    /// instead of the plain keyword match this file had before.
    ///
    /// Real-time-aware selection is unchanged from before consolidation:
    /// answers "where should I go right now" instead of assuming a fixed
    /// 8pm→10:30pm→12:30am evening progression. Every stop is picked and
    /// labeled from the venue's *actual* current status (live event /
    /// starting soon / open now / later tonight), never a hardcoded clock
    /// time, and closed venues with nothing happening are excluded
    /// entirely. Falls back to tomorrow's top picks — clearly labeled as
    /// such — only when literally nothing is active right now, so the feed
    /// is never empty.
    ///
    /// Runs on MainActor because it resolves l10n keys directly into final
    /// display text (badges, notes, the insider tip) — unlike the AI
    /// concierge's response, which already arrives as final text, this
    /// path has to produce the same shape from local string tables.
    @MainActor
    static func local(
        prompt: String,
        context: TripContext = TripContext(),
        venues: [BarPassVenue],
        userLocation: CLLocationCoordinate2D? = nil
    ) -> NightPlan {
        let now = Date()
        let l10n = L10n.shared

        // Real signal from ExperienceScorer: prompt keywords, vibe chips,
        // company type, inclusive prefs, live events, open-now, rating,
        // trending, distance — replaces the old hand-rolled keyword-only
        // `promptScore`/`distanceBonus` pair now that Plan carries the
        // same context Trips used to.
        func matchScore(_ v: BarPassVenue) -> Double {
            ExperienceScorer.score(venue: v, prompt: prompt, context: context, now: now, userCoordinate: userLocation)
        }
        func popularity(_ v: BarPassVenue) -> Double {
            (v.isTrending ? 1 : 0) + v.rating * 0.2 + min(Double(v.reviewCount) / 10_000, 0.5) + matchScore(v)
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
                venueSlug: c.venue.slug ?? c.venue.id,
                venueName: c.venue.name,
                note: l10n.t(c.noteKey),
                estimatedSpend: spendEstimate(for: c.venue.priceTier)
            )
        }

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespaces)
        let title = trimmedPrompt.isEmpty
            ? l10n.t("night.defaultTitle")
            : trimmedPrompt.prefix(1).uppercased() + trimmedPrompt.dropFirst()

        return NightPlan(
            title: title,
            summary: l10n.t("plan.summary.local"),
            stops: stops,
            totalEstimate: stops.reduce(0) { $0 + $1.estimatedSpend },
            insiderTip: String(format: l10n.t(isFallback ? "plan.insight.emptyFallback" : "plan.insight.live"), stops.first?.venueName ?? "")
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

    /// Representative per-person spend for a price tier — same buckets
    /// `PromptYourNightHomeSection.Budget` used ($25/$50/$100/$150+), so a
    /// local-fallback plan's `totalEstimate` reads consistently with what
    /// the AI concierge would have produced.
    private static func spendEstimate(for tier: PriceTier) -> Double {
        switch tier {
        case .unknown: return 60
        case .tier1:   return 25
        case .tier2:   return 50
        case .tier3:   return 100
        case .tier4:   return 175
        }
    }
}
