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
    /// **This is currently the ONLY engine running in production** (the key
    /// isn't set), so its ranking quality matters as much as the AI's.
    ///
    /// This is also where the old Trips "Prompt Your Night" flow's
    /// functionality landed after consolidation: vibe chips, company type
    /// and inclusive prefs (now merged into `PlanView`) feed `context` here
    /// and are scored via `ExperienceScorer` — the same engine Trips used —
    /// instead of the plain keyword match this file had before.
    ///
    /// Bug-fix log (2026-09-02, code review of the consolidation PR): three
    /// data-quality guardrails that lived in the two deleted files
    /// (`PromptYourNightView.swift`, `PromptYourNightHomeSection.swift`)
    /// were dropped during consolidation and are restored here:
    ///  1. A "known venue" fame boost (`fameBoost`) — without it, a low-
    ///     profile venue that loosely matches a keyword can outrank a
    ///     famous one (TestFlight: "por qué recomiendas lugares que tú no
    ///     irías").
    ///  2. A hard type filter per selected vibe (with a genre exemption) —
    ///     without it, a restaurant can outrank an actual club for a
    ///     "party" request (TestFlight: "los que son restaurante son
    ///     restaurantes...").
    ///  3. A hard price-range filter (`priceRange`, `.unknown` tier always
    ///     excluded when a range is active) and a genre-match boost for a
    ///     genre typed in free text — without them, "cheap" and "house
    ///     music" requests had no reliable effect (TestFlight: an Airport
    ///     Lounge for a $25 search; a house request that returned no house
    ///     venues).
    ///
    /// Runs on MainActor because it resolves l10n keys directly into final
    /// display text (badges, notes, the insider tip) — unlike the AI
    /// concierge's response, which already arrives as final text, this
    /// path has to produce the same shape from local string tables.
    ///
    /// - Parameter priceRange: `PriceTier.rawValue` bounds (1...4) the
    ///   result must fall within — `.unknown` (rawValue 0) is always
    ///   excluded when a range is given, same as the deleted budget
    ///   filter's bypass fix. `nil` means no price constraint. Falls back
    ///   to the unfiltered catalog if the constraint would leave zero
    ///   candidates, rather than showing an empty plan over a budget chip.
    /// - Parameter maxStops: same Free/Premium split as the AI concierge's
    ///   `stopCountBlock` (barpass-v2/.../concierge-prompt.ts) — Free stays
    ///   short (04_FREE_PLAN_SPEC.md: no "unlimited multi-step reasoning"),
    ///   Premium gets the full itinerary (05_PREMIUM_AI_SPEC.md "Complete-
    ///   night itinerary planning"). Defaults to the pre-tier value (4) for
    ///   any other caller.
    @MainActor
    static func local(
        prompt: String,
        context: TripContext = TripContext(),
        venues: [BarPassVenue],
        userLocation: CLLocationCoordinate2D? = nil,
        priceRange: ClosedRange<Int>? = nil,
        maxStops: Int = 4
    ) -> NightPlan {
        let now = Date()
        let l10n = L10n.shared

        // Price filter first — a hard constraint like the deleted budget
        // chips had, not a soft scoring nudge, but never allowed to leave
        // the feed empty (falls back to the unfiltered catalog below).
        var eligibleVenues = venues
        if let priceRange {
            let filtered = venues.filter { priceRange.contains($0.priceTier.rawValue) }
            if !filtered.isEmpty { eligibleVenues = filtered }
        }

        // A genre typed in free text (no chip needed) — used both to
        // exempt a venue from the type filter below and to boost it in
        // scoring, restoring the deleted detectGenre()/float-to-top fix.
        let effectiveGenre = detectGenre(in: prompt)

        // Hard type filter per selected vibe/intent — restores the deleted
        // "restaurant stays a restaurant, club stays a club" fix. Union
        // across every selected intent (Plan's picker is multi-select,
        // unlike the deleted single-select Home section this was ported
        // from); a venue carrying the detected genre is exempt, same as
        // before. Never allowed to leave the feed empty.
        let allowedTypes = Set(context.resolvedIntents.flatMap { $0.profile.preferredTypes })
        if !allowedTypes.isEmpty {
            let typeFiltered = eligibleVenues.filter { v in
                allowedTypes.contains(v.type) || (effectiveGenre != nil && v.musicGenres.contains(effectiveGenre!))
            }
            if !typeFiltered.isEmpty { eligibleVenues = typeFiltered }
        }

        // Real signal from ExperienceScorer: prompt keywords, vibe chips,
        // company type, inclusive prefs, live events, open-now, distance —
        // replaces the old hand-rolled keyword-only `promptScore`/
        // `distanceBonus` pair now that Plan carries the same context Trips
        // used. `fameBoost` restores the deleted "known venue" signal
        // (ExperienceScorer's own popularity term caps at +0.5 — too weak
        // on its own, per the TestFlight complaint that fix addressed).
        func fameBoost(_ v: BarPassVenue) -> Double {
            min(Double(v.reviewCount) / 500.0, 6.0)
        }
        func matchScore(_ v: BarPassVenue) -> Double {
            ExperienceScorer.score(venue: v, prompt: prompt, context: context, now: now, userCoordinate: userLocation)
        }
        func popularity(_ v: BarPassVenue) -> Double {
            var score = (v.isTrending ? 1 : 0) + matchScore(v) + fameBoost(v)
            if let effectiveGenre, v.musicGenres.contains(effectiveGenre) { score += 5 }
            return score
        }

        struct Candidate { let venue: BarPassVenue; let tier: Int; let rankScore: Double; let time: String; let noteKey: String }
        var candidates: [Candidate] = []

        for v in eligibleVenues {
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
            // Score computed once per venue (not inside the sort
            // comparator, which would recompute ExperienceScorer.score
            // O(n log n) times) and reused for the final Candidate.
            isFallback = true
            let fallbackSource = eligibleVenues.isEmpty ? venues : eligibleVenues
            ranked = fallbackSource
                .map { ($0, popularity($0)) }
                .sorted { $0.1 > $1.1 }
                .prefix(maxStops)
                .map { Candidate(venue: $0.0, tier: 4, rankScore: $0.1, time: l10n.t("plan.badge.tomorrow"), noteKey: "plan.note.tomorrow") }
        }

        let picks = Array(ranked.prefix(maxStops))
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
    /// `PlanBudgetOption` (PlanView.swift) uses for its budget chips, so a
    /// local-fallback plan's `totalEstimate` reads consistently with what
    /// the AI concierge would produce.
    private static func spendEstimate(for tier: PriceTier) -> Double {
        switch tier {
        case .unknown: return 60
        case .tier1:   return 25
        case .tier2:   return 50
        case .tier3:   return 100
        case .tier4:   return 175
        }
    }

    /// Matches a `MusicGenre` by its own raw value plus the handful of
    /// Spanish/alternate spellings someone would actually type — ported
    /// verbatim from the deleted `PromptYourNightHomeSection.detectGenre`
    /// (2026-09-02 bug-fix restoration, see `local`'s doc comment).
    private static func detectGenre(in prompt: String) -> MusicGenre? {
        let text = prompt.lowercased()
        let synonyms: [MusicGenre: [String]] = [
            .edm: ["edm", "electronica", "electrónica", "electronic"],
            .house: ["house", "techno"],
            .latin: ["latin", "latino", "latina"],
            .hipHop: ["hip hop", "hip-hop", "hiphop", "rap"],
            .reggaeton: ["reggaeton", "reggaetón"],
            .pop: ["pop"],
            .live: ["live music", "música en vivo", "musica en vivo", "banda en vivo"],
            .jazz: ["jazz"],
            .techHouse: ["tech house"],
            .rnb: ["r&b", "rnb", "r & b"],
        ]
        for genre in MusicGenre.allCases {
            let words = [genre.rawValue.lowercased()] + (synonyms[genre] ?? [])
            if words.contains(where: { text.contains($0) }) { return genre }
        }
        return nil
    }
}
