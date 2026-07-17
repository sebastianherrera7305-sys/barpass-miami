import Foundation

// MARK: - Experience Intent Engine
//
// The intent layer that turns "what moment do you want?" into a real,
// scored route over live venues. Deliberately experience-based, never
// demographic — an intent describes the moment the user wants, not who
// they are. Every intent maps ONLY to signals that exist in real venue
// data today (VenueType, MusicGenre, and the free-text vibes/tags arrays),
// so nothing here fabricates venue attributes. Intents whose ideal match
// isn't well-represented in the current (Miami nightlife) dataset simply
// surface the closest real venues rather than inventing perfect ones.

enum ExperienceIntent: String, Codable, CaseIterable, Identifiable {
    case celebrate
    case relax
    case meetPeople
    case watchSports
    case liveMusic
    case foodExperience
    case dateNight
    case familyTime
    case networking
    case cultural
    case adventure
    case nightlife

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .celebrate:     return "🎉"
        case .relax:         return "🍷"
        case .meetPeople:    return "🤝"
        case .watchSports:   return "🏟️"
        case .liveMusic:     return "🎵"
        case .foodExperience:return "🍽️"
        case .dateNight:     return "❤️"
        case .familyTime:    return "👨‍👩‍👧"
        case .networking:    return "💼"
        case .cultural:      return "🌎"
        case .adventure:     return "🌴"
        case .nightlife:     return "🌃"
        }
    }

    /// l10n key for the display label.
    var labelKey: String { "intent.\(rawValue)" }

    /// Free-text signals matched against a venue's searchable haystack
    /// (type + name + neighborhood + vibes + tags + musicGenres). Only terms
    /// that plausibly appear in real venue data — no invented attributes.
    var keywords: [String] {
        switch self {
        case .celebrate:      return ["club", "party", "bottle", "vip", "packed", "edm", "house"]
        case .relax:          return ["lounge", "chill", "rooftop", "cocktail", "wine", "speakeasy"]
        case .meetPeople:     return ["bar", "social", "lively", "trending", "packed"]
        case .watchSports:    return ["sports", "game", "beer", "brewery"]
        case .liveMusic:      return ["live", "jazz", "salsa", "band", "latin", "music"]
        case .foodExperience: return ["restaurant", "dinner", "food", "tasting", "chef"]
        case .dateNight:      return ["romantic", "date", "intimate", "views", "rooftop", "wine", "upscale"]
        case .familyTime:     return ["restaurant", "food", "casual"]
        case .networking:     return ["upscale", "lounge", "cocktail", "business", "hotel"]
        case .cultural:       return ["art", "live", "jazz", "local", "historic", "gallery"]
        case .adventure:      return ["rooftop", "beach", "outdoor", "views", "waterfront"]
        case .nightlife:      return ["club", "edm", "house", "techno", "late", "packed"]
        }
    }

    /// Experience Tag ids (see `ExperienceTag`) this intent should boost
    /// when a venue actually has them — a second, richer signal alongside
    /// `keywords`, sourced from real derived venue data instead of free-text
    /// matching. Deliberately conservative: only tag ids the rule engine in
    /// `derive-experience-tags.ts` can actually produce appear here.
    var relevantTagIds: [String] {
        switch self {
        case .celebrate:      return ["group_night", "high_energy"]
        case .relax:          return ["outdoor_experience", "scenic"]
        case .meetPeople:     return ["social", "group_night"]
        case .watchSports:    return ["sports_viewing"]
        case .liveMusic:      return ["live_music"]
        case .foodExperience: return ["vegetarian_friendly"]
        case .dateNight:      return ["date_friendly", "scenic"]
        case .familyTime:     return ["accessible"]
        case .networking:     return ["date_friendly", "social"]
        case .cultural:       return ["live_music", "scenic"]
        case .adventure:      return ["outdoor_experience", "scenic"]
        case .nightlife:      return ["high_energy", "group_night"]
        }
    }

    /// Venue types this intent leans toward, drawn from the existing
    /// `VenueType` enum — a soft ranking signal, never a hard filter.
    var preferredTypes: [VenueType] {
        switch self {
        case .celebrate:      return [.club, .rooftop]
        case .relax:          return [.lounge, .rooftop, .bar]
        case .meetPeople:     return [.bar, .lounge]
        case .watchSports:    return [.sportsBar, .brewery, .bar]
        case .liveMusic:      return [.lounge, .bar]
        case .foodExperience: return [.restaurant]
        case .dateNight:      return [.rooftop, .lounge, .restaurant]
        case .familyTime:     return [.restaurant]
        case .networking:     return [.lounge, .rooftop, .bar]
        case .cultural:       return [.lounge, .bar]
        case .adventure:      return [.rooftop]
        case .nightlife:      return [.club]
        }
    }
}

// MARK: - Company context

/// Who the user is going out with. Tunes the recommendation toward the
/// shape of the group (e.g. a couple leans intimate, a work group leans
/// upscale) without ever making demographic assumptions about the people
/// themselves.
enum CompanyType: String, Codable, CaseIterable, Identifiable {
    case solo
    case friends
    case couple
    case family
    case workGroup
    case visitors

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .solo:      return "🧍"
        case .friends:   return "🎊"
        case .couple:    return "💑"
        case .family:    return "👨‍👩‍👧"
        case .workGroup: return "💼"
        case .visitors:  return "🧳"
        }
    }

    var labelKey: String { "company.\(rawValue)" }

    /// Extra keyword nudges layered on top of the chosen intent(s).
    var keywords: [String] {
        switch self {
        case .solo:      return ["bar", "lounge", "counter"]
        case .friends:   return ["lively", "group", "packed", "trending"]
        case .couple:    return ["romantic", "intimate", "views", "date"]
        case .family:    return ["restaurant", "casual", "food"]
        case .workGroup: return ["upscale", "lounge", "business"]
        case .visitors:  return ["iconic", "views", "trending", "rooftop"]
        }
    }
}

// MARK: - Experience Tags (Venue Intelligence Layer)

/// How certain a tag is, given what it was derived from. Never presented
/// to the user as a stated fact when it's actually an inference — see
/// `NightPlanner.reason`, which only surfaces a tag-based reason for
/// `.high` confidence matches.
enum TagConfidence: String, Codable {
    case high, medium, low
}

/// Where a tag came from — kept even after storage so a future audit or UI
/// can always answer "why does BarPass think this?"
enum TagSource: String, Codable {
    case googleAttribute = "google_attribute"
    case venueCategory   = "venue_category"
    case userSignal      = "user_signal"
    case futureAI        = "future_ai"
}

/// A single derived experience signal for a venue (e.g. "group_night",
/// "date_friendly"). Computed server-side by
/// `barpass-v2/scripts/derive-experience-tags.ts` from real, already-
/// enriched venue data — never fabricated, never AI-guessed today (the
/// `.futureAI` source exists as a reserved slot, not a live path). iOS only
/// ever reads these; the derivation rules live in exactly one place.
struct ExperienceTag: Codable, Hashable, Identifiable {
    let id: String
    let category: String
    let confidence: TagConfidence
    let source: TagSource
}

// MARK: - Inclusive preferences

/// Accessibility/atmosphere preferences a user can opt into. Each case maps
/// 1:1 to a real, Google-sourced `VenueAmenities` field — never a fabricated
/// attribute. As of the 2026-07-16 data audit, NO venue has amenity data
/// populated yet (enrich-venues.ts was just extended to fetch it, and it
/// hasn't been run against the live catalog) — so this enum and its scoring
/// hook exist, but there is intentionally no picker UI for it yet. Shipping
/// a filter UI that matches zero venues would look broken, not helpful;
/// wire up the UI once a real enrichment pass has populated some data.
enum InclusivePreference: String, Codable, CaseIterable, Identifiable {
    case wheelchairAccessible
    case outdoorSeating
    case goodForGroups
    case goodForWatchingSports
    case liveMusic
    case reservable
    case vegetarianFriendly
    case hasRestroom

    var id: String { rawValue }
    var labelKey: String { "inclusive.\(rawValue)" }

    /// Reads the matching field off a venue's real amenity data. Returns nil
    /// (unknown) rather than false when Google hasn't reported it — callers
    /// must not treat nil as "doesn't have this."
    func value(for venue: BarPassVenue) -> Bool? {
        switch self {
        case .wheelchairAccessible: return venue.amenities.wheelchairAccessible
        case .outdoorSeating:       return venue.amenities.outdoorSeating
        case .goodForGroups:        return venue.amenities.goodForGroups
        case .goodForWatchingSports:return venue.amenities.goodForWatchingSports
        case .liveMusic:            return venue.amenities.hasLiveMusic
        case .reservable:           return venue.amenities.reservable
        case .vegetarianFriendly:   return venue.amenities.servesVegetarianFood
        case .hasRestroom:          return venue.amenities.restroom
        }
    }
}

// MARK: - Trip context

/// The full "what experience, with whom, when, where" picture that drives a
/// recommendation. Codable so it can be persisted with a Trip later and,
/// eventually, handed to a server-side AI concierge unchanged — this is the
/// data-structure foundation the AI builder will sit on, deliberately built
/// now even though the AI itself is not.
struct TripContext: Codable, Hashable {
    var intents: Set<String> = []          // ExperienceIntent ids
    var company: CompanyType? = nil
    var date: Date = .now
    /// How long the outing should run — caps how many stops make sense.
    var durationHours: Double? = nil
    /// Max acceptable travel time between stops, in minutes. Reserved for
    /// distance-aware routing once venue-to-venue travel time is wired in.
    var maxTravelMinutes: Int? = nil
    /// Free-text natural-language prompt, unchanged from the existing flow.
    var prompt: String = ""
    /// Inclusive preference tags the user opted into (see
    /// `InclusivePreference`). Persisted and passed through scoring, but only
    /// actually filters on attributes the venue data really has — see that
    /// type's `hasRealData` flag.
    var inclusivePrefs: Set<String> = []

    var resolvedIntents: [ExperienceIntent] {
        intents.compactMap { ExperienceIntent(rawValue: $0) }
    }
}
