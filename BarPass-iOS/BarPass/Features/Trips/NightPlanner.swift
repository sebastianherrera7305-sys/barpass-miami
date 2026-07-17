import Foundation

/// Emotion-first night builder. Turns a set of vibe chips + a natural-language
/// prompt into a real, sequenced route (warm-up → peak) drawn ONLY from live
/// venues. Deterministic and local today; the same interface can be backed by
/// the AI Concierge later without touching the UI.
///
/// Scoring itself lives in `ExperienceScorer` (Core/Intelligence) — this type
/// now owns only what's genuinely Trips-specific: the legacy vibe-chip list,
/// phase sequencing (warm-up → mid → peak), and the duration-based stop cap.
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

    static func plan(venues: [BarPassVenue], selected: Set<String>, prompt: String, passport: MusicPassport? = nil, context: TripContext? = nil) -> [PlannedStop] {
        guard !venues.isEmpty else { return [] }
        let now = Date()

        let surprise = ExperienceScorer.isSurprise(selected: selected, prompt: prompt, context: context)

        var scored = venues.map { v in
            (v, ExperienceScorer.score(venue: v, selected: selected, prompt: prompt, passport: passport, context: context, now: now))
        }
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
            .map { PlannedStop(venue: $0, reason: ExperienceScorer.reason(venue: $0, prompt: prompt, passport: passport, context: context, now: now)) }
    }
}
