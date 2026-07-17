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

    /// All of this intent's compatibility signals in one place. Previously
    /// these lived as 4 independent switches (`keywords`, `preferredTypes`,
    /// `relevantTagIds`, `conflictingTagIds`) — real-data validation found a
    /// bug caused exactly by that shape: `conflictingTagIds` was added later
    /// than the other three, after a venue surfaced the gap, because nothing
    /// forced positive and negative signals to be defined together. One
    /// switch, one struct, so a new intent (or a new negative signal for an
    /// existing one) is a single edit instead of four.
    var profile: IntentProfile {
        switch self {
        case .celebrate:
            return IntentProfile(
                keywords: ["club", "party", "bottle", "vip", "packed", "edm", "house"],
                preferredTypes: [.club, .rooftop],
                positiveTagIds: ["group_night", "high_energy"],
                negativeTagIds: []
            )
        case .relax:
            return IntentProfile(
                keywords: ["lounge", "chill", "rooftop", "cocktail", "wine", "speakeasy"],
                preferredTypes: [.lounge, .rooftop, .bar],
                positiveTagIds: ["outdoor_experience", "scenic"],
                negativeTagIds: ["high_energy"]
            )
        case .meetPeople:
            return IntentProfile(
                keywords: ["bar", "social", "lively", "trending", "packed"],
                preferredTypes: [.bar, .lounge],
                positiveTagIds: ["social", "group_night"],
                negativeTagIds: []
            )
        case .watchSports:
            return IntentProfile(
                keywords: ["sports", "game", "beer", "brewery"],
                preferredTypes: [.sportsBar, .brewery, .bar],
                positiveTagIds: ["sports_viewing"],
                negativeTagIds: []
            )
        case .liveMusic:
            return IntentProfile(
                keywords: ["live", "jazz", "salsa", "band", "latin", "music"],
                preferredTypes: [.lounge, .bar],
                positiveTagIds: ["live_music"],
                negativeTagIds: []
            )
        case .foodExperience:
            return IntentProfile(
                keywords: ["restaurant", "dinner", "food", "tasting", "chef"],
                preferredTypes: [.restaurant],
                positiveTagIds: ["vegetarian_friendly"],
                negativeTagIds: ["high_energy"]
            )
        case .dateNight:
            return IntentProfile(
                keywords: ["romantic", "date", "intimate", "views", "rooftop", "wine", "upscale"],
                preferredTypes: [.rooftop, .lounge, .restaurant],
                positiveTagIds: ["date_friendly", "scenic"],
                negativeTagIds: ["high_energy"]
            )
        case .familyTime:
            return IntentProfile(
                keywords: ["restaurant", "food", "casual"],
                preferredTypes: [.restaurant],
                positiveTagIds: ["accessible"],
                negativeTagIds: ["high_energy"]
            )
        case .networking:
            return IntentProfile(
                keywords: ["upscale", "lounge", "cocktail", "business", "hotel"],
                preferredTypes: [.lounge, .rooftop, .bar],
                positiveTagIds: ["date_friendly", "social"],
                negativeTagIds: ["high_energy"]
            )
        case .cultural:
            return IntentProfile(
                keywords: ["art", "live", "jazz", "local", "historic", "gallery"],
                preferredTypes: [.lounge, .bar],
                positiveTagIds: ["live_music", "scenic"],
                negativeTagIds: []
            )
        case .adventure:
            return IntentProfile(
                keywords: ["rooftop", "beach", "outdoor", "views", "waterfront"],
                preferredTypes: [.rooftop],
                positiveTagIds: ["outdoor_experience", "scenic"],
                negativeTagIds: []
            )
        case .nightlife:
            return IntentProfile(
                keywords: ["club", "edm", "house", "techno", "late", "packed"],
                preferredTypes: [.club],
                positiveTagIds: ["high_energy", "group_night"],
                negativeTagIds: []
            )
        }
    }

    // MARK: Thin forwarders (migration scaffolding)
    //
    // Kept so NightPlanner didn't need to change in the same commit as this
    // consolidation. Delete once all call sites read `.profile` directly.
    var keywords: [String] { profile.keywords }
    var preferredTypes: [VenueType] { profile.preferredTypes }
    var relevantTagIds: [String] { profile.positiveTagIds }
    var conflictingTagIds: [String] { profile.negativeTagIds }
}

/// One intent's full compatibility signal set — see `ExperienceIntent.profile`.
struct IntentProfile {
    let keywords: [String]
    let preferredTypes: [VenueType]
    let positiveTagIds: [String]
    let negativeTagIds: [String]
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

    /// Never claim more certainty than a tag's own confidence supports.
    /// Used identically whether a tag is boosting a positive match or
    /// penalizing a conflict — same scale both directions.
    var weight: Double {
        switch self {
        case .high:   return 1.0
        case .medium: return 0.6
        case .low:    return 0.3
        }
    }
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
