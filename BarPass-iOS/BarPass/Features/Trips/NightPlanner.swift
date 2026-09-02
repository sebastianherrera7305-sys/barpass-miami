import Foundation

/// Shared building blocks for "what moment is this venue right for" —
/// `ExperienceScorer` (Core/Intelligence) does the actual scoring, `Stop
/// .sequence` (Models/Trip.swift) uses `phase(of:)` to order a Trip's stops,
/// and `NightPlan.local` (Models/NightPlan.swift, the Plan tab's offline
/// fallback) pulls in `vibes` via `ExperienceScorer`. The old route-building
/// entry point (`plan(venues:selected:prompt:...)`, used only by Trips'
/// "Prompt Your Night" flow) was retired 2026-09-01 when that flow was
/// merged into `PlanView` — see CLAUDE.md → "Plan Consolidation Roadmap".
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
}
