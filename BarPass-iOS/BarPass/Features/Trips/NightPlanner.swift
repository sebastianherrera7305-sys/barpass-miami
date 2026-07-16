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

    static func plan(venues: [BarPassVenue], selected: Set<String>, prompt: String, passport: MusicPassport? = nil) -> [PlannedStop] {
        guard !venues.isEmpty else { return [] }
        let now = Date()

        let surprise = selected.contains("surprise")
            || (selected.isEmpty && prompt.trimmingCharacters(in: .whitespaces).isEmpty)

        let vibeKeys = vibes.filter { selected.contains($0.id) }.flatMap { $0.keywords }
        let promptKeys = prompt.lowercased()
            .split { !$0.isLetter }.map(String.init).filter { $0.count > 3 }
        let keys = Set(vibeKeys + promptKeys)

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

        var chosen: [BarPassVenue] = []
        for p in [0, 1, 2] {
            if let cand = pool.first(where: { c in
                phase(of: c) == p && !chosen.contains(where: { $0.id == c.id })
            }) { chosen.append(cand) }
        }
        for v in pool where chosen.count < 4 {
            if !chosen.contains(where: { $0.id == v.id }) { chosen.append(v) }
        }
        return chosen
            .sorted { phase(of: $0) < phase(of: $1) }
            .map { PlannedStop(venue: $0, reason: reason($0)) }
    }
}
