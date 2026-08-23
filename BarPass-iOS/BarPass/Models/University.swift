import Foundation

/// A real university, sourced from its own official site — never invented.
/// `city` matches the same short-name convention as `BarPassVenue.city`
/// (e.g. "Gainesville", not "Gainesville, FL") so it lines up with the
/// existing city filter.
struct University: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let shortName: String?
    let city: String
    /// The BarPass venue-city metro area this university belongs to, when it
    /// differs from `city` (e.g. Coral Gables → Miami). A real geographic
    /// fact, never invented. Falls back to `city` when nil.
    let metroCity: String?
    let state: String?
    let country: String
    let officialURL: String?
    let greekLifeURL: String?
    let lat: Double?
    let lng: Double?
    /// A real, sourced fact only (e.g. "IFC governs 26 fraternities per the
    /// official office") — never a vibe/marketing line. nil when no such
    /// fact was found during research.
    let partyLifeNotes: String?

    /// Which BarPass venue city to filter by for "nightlife near here".
    var venueCity: String { metroCity ?? city }
}

enum GreekCouncil: String, Codable, CaseIterable {
    case ifc = "IFC"
    case nphc = "NPHC"
    case mgc = "MGC"
    case panhellenic = "Panhellenic"
    case other = "Other"

    var label: String {
        switch self {
        case .ifc: return "Interfraternity Council"
        case .nphc: return "National Pan-Hellenic Council"
        case .mgc: return "Multicultural Greek Council"
        case .panhellenic: return "Panhellenic"
        case .other: return "Other"
        }
    }
}

/// Never defaults to `.active` — a chapter research pass that couldn't
/// confirm current status stays `.unknown`, on purpose.
enum ChapterStatus: String, Codable {
    case active, suspended, inactive, historical, unknown

    @MainActor var label: String {
        switch self {
        case .active: return L10n.shared.t("greek.status.active")
        case .suspended: return L10n.shared.t("greek.status.suspended")
        case .inactive: return L10n.shared.t("greek.status.inactive")
        case .historical: return L10n.shared.t("greek.status.historical")
        case .unknown: return L10n.shared.t("greek.status.unknown")
        }
    }
}

/// A real fraternity chapter at a specific university. Every row must trace
/// back to `officialSourceURL` — that field is what makes this different
/// from a plausible-looking guess.
struct GreekChapter: Identifiable, Codable, Hashable {
    let id: String
    let universityId: String
    let fraternityName: String
    let chapterDesignation: String?
    let council: GreekCouncil
    let status: ChapterStatus
    let officialSourceURL: String
    let chapterURL: String?
    let address: String?
    let lat: Double?
    let lng: Double?
    let addressVerified: Bool
    let needsReview: Bool
    let reviewReason: String?
}
