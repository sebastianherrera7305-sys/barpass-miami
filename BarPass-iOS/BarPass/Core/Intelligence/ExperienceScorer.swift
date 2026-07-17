import Foundation

/// General-purpose "how good is this venue for this intent+context" scoring
/// — Engine V2 consolidation, Step 3 (see EXPERIENCE_ENGINE_V2_ARCHITECTURE.md
/// §8). Extracted verbatim from `NightPlanner.score()`/`reason()`: same
/// formula, same branches, same weights — just moved so a second consumer
/// (Home Feed) can call it without pulling in Trips' phase-sequencing/
/// duration-cap logic, which stays in `NightPlanner`.
///
/// `passport` stays a separate parameter rather than folding into
/// `TripContext` — see Step 0 of the migration: `TripContext` is Codable
/// and shaped for a future AI concierge payload, and a user's local Apple
/// Music profile doesn't belong serialized alongside "what experience do
/// you want."
enum ExperienceScorer {

    /// True when the caller gave no explicit signal at all (no vibe chips,
    /// no intent, no company, no prompt) — the "surprise me" formula branch
    /// applies. Exposed so callers that post-filter low scorers (see
    /// `NightPlanner.plan`) can skip that filter under the same condition,
    /// without duplicating this exact boolean logic a second time.
    static func isSurprise(selected: Set<String>, prompt: String, context: TripContext?) -> Bool {
        let intents = context?.resolvedIntents ?? []
        let noExplicitInput = selected.isEmpty && intents.isEmpty
            && (context?.company == nil)
            && prompt.trimmingCharacters(in: .whitespaces).isEmpty
        return selected.contains("surprise") || noExplicitInput
    }

    /// Multi-signal score over REAL data: vibe/prompt/intent match + live
    /// events + open-now + happy hour + popularity + rating + experience
    /// tags (confidence-weighted, both positive matches and negative
    /// conflicts) + inclusive preferences + music taste. Weather/wait-times
    /// are intentionally absent — no data source yet, never faked.
    static func score(
        venue v: BarPassVenue,
        selected: Set<String> = [],
        prompt: String = "",
        passport: MusicPassport? = nil,
        context: TripContext? = nil,
        now: Date = Date()
    ) -> Double {
        let intents = context?.resolvedIntents ?? []
        let intentKeys = intents.flatMap { $0.keywords }
        let companyKeys = context?.company?.keywords ?? []
        let preferredTypes = Set(intents.flatMap { $0.preferredTypes })
        let relevantTagIds = Set(intents.flatMap { $0.relevantTagIds })
        let conflictingTagIds = Set(intents.flatMap { $0.conflictingTagIds })

        let surprise = isSurprise(selected: selected, prompt: prompt, context: context)

        let vibeKeys = NightPlanner.vibes.filter { selected.contains($0.id) }.flatMap { $0.keywords }
        let promptKeys = (prompt + " " + (context?.prompt ?? "")).lowercased()
            .split { !$0.isLetter }.map(String.init).filter { $0.count > 3 }
        let keys = Set(vibeKeys + promptKeys + intentKeys + companyKeys)

        func haystack(_ v: BarPassVenue) -> String {
            ([v.type.rawValue, v.name, v.neighborhood] + v.vibes + v.tags
                + v.musicGenres.map { $0.rawValue }).joined(separator: " ").lowercased()
        }
        func matchedExperienceTags(_ v: BarPassVenue) -> [ExperienceTag] {
            guard !relevantTagIds.isEmpty else { return [] }
            return v.experienceTags.filter { relevantTagIds.contains($0.id) }
        }

        var s: Double
        if surprise {
            s = (v.isTrending ? 2 : 0) + v.rating
        } else {
            let h = haystack(v)
            s = Double(keys.filter { h.contains($0) }.count)
            if selected.contains("trending") && v.isTrending { s += 2 }
            s += v.rating * 0.15
        }
        // Experience-intent type preference: a soft boost when the venue's
        // type is one the chosen intent leans toward (real VenueType data,
        // never a hard filter — the closest real venue still surfaces even
        // with no perfect type match).
        if !preferredTypes.isEmpty && preferredTypes.contains(v.type) { s += 1.0 }
        // Experience Tags (Venue Intelligence Layer): confidence-weighted
        // boost — a high-confidence tag (single Google attribute) counts
        // more than a medium one (category-combined inference). Additive
        // per matched tag, never a hard filter.
        for tag in matchedExperienceTags(v) { s += tag.confidence.weight }
        // Conflicting tags: found via real-data validation — "relax"
        // surfaced a high_energy club in its top picks because nothing
        // penalized a tag that actively contradicts the intent, only
        // matches were rewarded. Soft penalty, same weight scale as a
        // match, never an outright exclusion.
        if !conflictingTagIds.isEmpty {
            let conflicts = v.experienceTags.filter { conflictingTagIds.contains($0.id) }
            for tag in conflicts { s -= tag.confidence.weight }
        }
        // Inclusive preferences: boost only when Google actually reported
        // the attribute as true. Unknown (nil, the common case today,
        // since no enrichment pass has populated amenities yet) is
        // treated as neutral, never as a penalty — a venue is never
        // excluded for lacking data it was simply never asked for.
        if let inclusivePrefs = context?.inclusivePrefs, !inclusivePrefs.isEmpty {
            let matched = inclusivePrefs.compactMap { InclusivePreference(rawValue: $0) }
                .filter { $0.value(for: v) == true }.count
            s += Double(matched) * 0.6
        }
        if eventTonight(v, now: now) != nil { s += 2.5 }          // strongest live signal
        if v.isOpenNow { s += 0.75 }
        if v.hasHappyHour { s += 0.4 }
        if let passport { s += HypeEngine.musicMatch(passport: passport, venue: v) * 1.5 }
        s += min(Double(v.reviewCount) / 10_000.0, 0.5)           // popularity, capped
        return s
    }

    /// Human-readable "why this venue" string — only ever states a tag-based
    /// reason for `.high` confidence matches (see `NightPlanner.reasonLabel`);
    /// medium/low-confidence tags still influence `score` above, but are an
    /// inference, not a fact, and must not be presented as one.
    static func reason(
        venue v: BarPassVenue,
        prompt: String = "",
        passport: MusicPassport? = nil,
        context: TripContext? = nil,
        now: Date = Date()
    ) -> String? {
        let intents = context?.resolvedIntents ?? []
        let relevantTagIds = Set(intents.flatMap { $0.relevantTagIds })
        func matchedExperienceTags(_ v: BarPassVenue) -> [ExperienceTag] {
            guard !relevantTagIds.isEmpty else { return [] }
            return v.experienceTags.filter { relevantTagIds.contains($0.id) }
        }

        if let e = eventTonight(v, now: now) { return "🎟️ \(e.title) esta noche" }
        if let passport, HypeEngine.musicMatch(passport: passport, venue: v) >= 0.6 {
            return "🎵 Match con tu música"
        }
        if let tag = matchedExperienceTags(v).first(where: { $0.confidence == .high }) {
            return "✨ " + NightPlanner.reasonLabel(for: tag.id)
        }
        if v.hasHappyHour, let until = v.happyHourUntil { return "🍹 Happy hour hasta \(until)" }
        if v.isTrending { return "🔥 Trending ahora" }
        if v.reviewCount > 5000 { return "⭐ Favorito de Miami (\(v.reviewCount) reviews)" }
        return nil
    }

    /// Tonight's event for a venue, if any — live right now, ending soon, or
    /// starting within the next 12h. Events already over (per
    /// `VenueTimeStatus`'s assumed duration) never match.
    fileprivate static func eventTonight(_ v: BarPassVenue, now: Date) -> VenueEvent? {
        v.upcomingEvents.first { event in
            switch VenueTimeStatus.status(for: event, now: now) {
            case .liveNow, .endingSoon:       return true
            case .upcoming(let startsInMins): return startsInMins <= 12 * 60
            case .finished:                   return false
            }
        }
    }
}
