import Foundation

/// Emotion-first night builder. Turns a set of vibe chips + a natural-language
/// prompt into a real, sequenced route (warm-up → peak) drawn ONLY from live
/// venues. Deterministic and local today; the same interface can be backed by
/// the AI Concierge later without touching the UI.
struct NightVibe: Identifiable, Hashable {
    let id: String
    let emoji: String
    let label: String
    let keywords: [String]
}

enum NightPlanner {
    static let vibes: [NightVibe] = [
        .init(id: "rooftops", emoji: "🍸", label: "Rooftops", keywords: ["rooftop", "sunset", "views", "garden"]),
        .init(id: "party", emoji: "🎉", label: "Party hasta el amanecer", keywords: ["club", "edm", "house", "techno", "packed"]),
        .init(id: "date", emoji: "🥂", label: "Cita elegante", keywords: ["date", "lounge", "restaurant", "romantic", "upscale", "views"]),
        .init(id: "food", emoji: "🍣", label: "Food adventure", keywords: ["restaurant", "dinner", "food"]),
        .init(id: "live", emoji: "🎵", label: "Música en vivo", keywords: ["live", "jazz", "salsa", "latin"]),
        .init(id: "trending", emoji: "🔥", label: "Trending", keywords: ["trending"]),
        .init(id: "hidden", emoji: "✨", label: "Hidden gems", keywords: ["hidden", "local", "lounge"]),
        .init(id: "girls", emoji: "💃", label: "Girls night", keywords: ["club", "latin", "reggaeton", "cocktail"]),
        .init(id: "surprise", emoji: "🎭", label: "Sorprendeme", keywords: []),
    ]

    /// Human-readable label for a high-confidence Experience Tag match —
    /// only called for `.high` confidence, so every string here states
    /// something the tag's source (a direct Google attribute) actually
    /// confirms, never a guess.
    static func reasonLabel(for tagId: String) -> String {
        switch tagId {
        case "live_music":           return "Música en vivo confirmada"
        case "group_night":          return "Ideal para ir en grupo"
        case "outdoor_experience":   return "Tiene espacio al aire libre"
        case "sports_viewing":       return "Bueno para ver el partido"
        case "accessible":           return "Accesible en silla de ruedas"
        case "vegetarian_friendly":  return "Opciones vegetarianas"
        default:                     return tagId.replacingOccurrences(of: "_", with: " ")
        }
    }

    static func phase(of v: BarPassVenue) -> Int {
        switch v.type {
        case .rooftop, .restaurant: return 0   // warm-up
        case .club:                 return 2   // peak
        default:                    return 1
        }
    }

    /// A planned stop plus the strongest live signal that put it there.
    struct PlannedStop: Identifiable {
        let venue: BarPassVenue
        let reason: String?
        var id: String { venue.id }
    }

    /// Tonight's event for a venue, if any — live right now, ending soon, or
    /// starting within the next 12h. Events already over (per
    /// `VenueTimeStatus`'s assumed duration) never match, unlike the old
    /// `-6h/+30h` window that kept "finished" events alive for 6 more hours.
    private static func eventTonight(_ v: BarPassVenue, now: Date) -> VenueEvent? {
        v.upcomingEvents.first { event in
            switch VenueTimeStatus.status(for: event, now: now) {
            case .liveNow, .endingSoon:       return true
            case .upcoming(let startsInMins): return startsInMins <= 12 * 60
            case .finished:                   return false
            }
        }
    }

    static func plan(venues: [BarPassVenue], selected: Set<String>, prompt: String, passport: MusicPassport? = nil, context: TripContext? = nil) -> [PlannedStop] {
        guard !venues.isEmpty else { return [] }
        let now = Date()

        // Experience-intent + company signals fold in on top of the existing
        // vibe chips — same keyword-matching model, richer input. All map to
        // terms that exist in real venue data (types/genres/vibes/tags).
        let intents = context?.resolvedIntents ?? []
        let intentKeys = intents.flatMap { $0.keywords }
        let companyKeys = context?.company?.keywords ?? []
        let preferredTypes = Set(intents.flatMap { $0.preferredTypes })
        let relevantTagIds = Set(intents.flatMap { $0.relevantTagIds })
        let conflictingTagIds = Set(intents.flatMap { $0.conflictingTagIds })

        func matchedExperienceTags(_ v: BarPassVenue) -> [ExperienceTag] {
            guard !relevantTagIds.isEmpty else { return [] }
            return v.experienceTags.filter { relevantTagIds.contains($0.id) }
        }

        let noExplicitInput = selected.isEmpty && intents.isEmpty
            && (context?.company == nil)
            && prompt.trimmingCharacters(in: .whitespaces).isEmpty
        let surprise = selected.contains("surprise") || noExplicitInput

        let vibeKeys = vibes.filter { selected.contains($0.id) }.flatMap { $0.keywords }
        let promptKeys = (prompt + " " + (context?.prompt ?? "")).lowercased()
            .split { !$0.isLetter }.map(String.init).filter { $0.count > 3 }
        let keys = Set(vibeKeys + promptKeys + intentKeys + companyKeys)

        func haystack(_ v: BarPassVenue) -> String {
            ([v.type.rawValue, v.name, v.neighborhood] + v.vibes + v.tags
                + v.musicGenres.map { $0.rawValue }).joined(separator: " ").lowercased()
        }

        // Multi-signal score over REAL data: vibe/prompt match + live events
        // + open-now + happy hour + popularity + rating. Weather/wait-times
        // are intentionally absent — no data source yet, never faked.
        func score(_ v: BarPassVenue) -> Double {
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

        func reason(_ v: BarPassVenue) -> String? {
            if let e = eventTonight(v, now: now) { return "🎟️ \(e.title) esta noche" }
            if let passport, HypeEngine.musicMatch(passport: passport, venue: v) >= 0.6 {
                return "🎵 Match con tu música"
            }
            // Only ever state a tag-based reason for `.high` confidence — a
            // medium/low-confidence tag still boosts score above, but is an
            // inference, not a fact, and must not be presented as one.
            if let tag = matchedExperienceTags(v).first(where: { $0.confidence == .high }) {
                return "✨ " + NightPlanner.reasonLabel(for: tag.id)
            }
            if v.hasHappyHour, let until = v.happyHourUntil { return "🍹 Happy hour hasta \(until)" }
            if v.isTrending { return "🔥 Trending ahora" }
            if v.reviewCount > 5000 { return "⭐ Favorito de Miami (\(v.reviewCount) reviews)" }
            return nil
        }

        var scored = venues.map { ($0, score($0)) }
        if !surprise && scored.contains(where: { $0.1 >= 1 }) {
            scored = scored.filter { $0.1 >= 1 }
        }
        // Never recommend a closed venue while an open one is available.
        if scored.contains(where: { $0.0.isOpenNow }) {
            scored = scored.filter { $0.0.isOpenNow }
        }
        let ranked = scored.sorted { $0.1 > $1.1 }.map { $0.0 }
        let pool = Array(ranked.prefix(12))

        // Shorter outings get fewer stops — a 2-hour after-work relax shouldn't
        // return a full 4-stop crawl. ~1 stop per 1.5h, clamped to 1...4.
        let maxStops: Int = {
            guard let hours = context?.durationHours else { return 4 }
            return min(4, max(1, Int((hours / 1.5).rounded(.up))))
        }()

        var chosen: [BarPassVenue] = []
        for p in [0, 1, 2] {
            if let cand = pool.first(where: { c in
                phase(of: c) == p && !chosen.contains(where: { $0.id == c.id })
            }) { chosen.append(cand) }
        }
        for v in pool where chosen.count < maxStops {
            if !chosen.contains(where: { $0.id == v.id }) { chosen.append(v) }
        }
        chosen = Array(chosen.prefix(maxStops))
        return chosen
            .sorted { phase(of: $0) < phase(of: $1) }
            .map { PlannedStop(venue: $0, reason: reason($0)) }
    }
}
