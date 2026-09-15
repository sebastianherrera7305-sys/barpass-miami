import Foundation

/// A night run by a host (a promoter, a chapter social chair) on top of a
/// venue from our own catalogue.
///
/// Mirrors the wire shapes returned by `barpass-v2/src/app/api/host-events/*`
/// (`host-event-dto.ts`). The DATABASE is the authority on every rule —
/// availability, queue position, claim windows — so nothing here recomputes
/// them; these types just carry what the server already decided.
///
/// Two things the UI must never fake:
/// • the venue is an id from the verified catalogue, never free text;
/// • `purchasable` is false on every paid tier today (Stripe has charges
///   disabled), so a paid tier is shown as unavailable, never as buyable.

// MARK: - Enums

/// Unknown values decode rather than throw: the server may learn a new state
/// before this build does, and a listing that fails to parse is worse than
/// one showing a conservative default.
enum HostEventStatus: String, Codable, Sendable {
    case draft, published, cancelled

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HostEventStatus(rawValue: raw) ?? .draft
    }
}

/// Can this tier be claimed right now? Half-open window: [start, end).
enum HostEventSalesState: String, Codable, Sendable {
    case notYetOpen = "not_yet_open"
    case open
    case closed

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HostEventSalesState(rawValue: raw) ?? .closed
    }
}

/// The door's window — "valid 10–11 PM". Separate from sales on purpose:
/// holding a ticket does not mean you may walk in whenever.
enum HostEventEntryValidity: String, Codable, Sendable {
    case notYetValid = "not_yet_valid"
    case valid
    case expired

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HostEventEntryValidity(rawValue: raw) ?? .expired
    }
}

enum HostEventWaitlistState: String, Codable, Sendable {
    case waiting, offered, claimed, expired, left

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HostEventWaitlistState(rawValue: raw) ?? .waiting
    }
}

// MARK: - Event

struct HostEventVenueRef: Codable, Hashable, Sendable {
    let id: String
    /// Null on the PATCH response, which doesn't re-join the venue row — the
    /// caller already knows the name in that case, so this is not an error.
    let name: String?
    let slug: String?
}

struct HostEvent: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let hostId: String
    let venue: HostEventVenueRef
    let title: String
    let description: String
    let startsAt: Date
    let endsAt: Date?
    let status: HostEventStatus
    /// The organiser's master switch over the guest list. Each attendee holds
    /// their own switch too; both must be on for a name to be public.
    let attendeeListPublic: Bool
    let claimWindowMinutes: Int
    let coverImageUrl: String?
    let cancelledAt: Date?
    let createdAt: Date

    var isCancelled: Bool { status == .cancelled || cancelledAt != nil }
}

// MARK: - Tier

struct HostEventTier: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let description: String?
    let priceCents: Int
    let isFree: Bool
    /// False on every paid tier until Stripe is live. The server refuses a
    /// paid RSVP with 501 regardless; this is what lets the UI say so first.
    let purchasable: Bool
    let quantity: Int
    /// Counts live waitlist offers against capacity, same as the database —
    /// a seat mid-claim is not a seat on sale.
    let remaining: Int
    let soldOut: Bool
    let salesStartAt: Date
    let salesEndAt: Date
    let salesState: HostEventSalesState
    let entryValidFrom: Date
    let entryValidUntil: Date
    let sortOrder: Int

    /// The only action a client may offer on a tier, decided here once so no
    /// view re-derives it wrongly.
    enum Action { case rsvp, joinWaitlist, salesNotOpen, salesClosed, paidNotEnabled }

    var action: Action {
        if !purchasable { return .paidNotEnabled }
        switch salesState {
        case .notYetOpen: return .salesNotOpen
        case .closed:     return .salesClosed
        case .open:       return soldOut ? .joinWaitlist : .rsvp
        }
    }
}

struct HostEventDetail: Sendable {
    let event: HostEvent
    let tiers: [HostEventTier]
    let paidTiersEnabled: Bool
}

// MARK: - RSVP / waitlist / attendees

struct HostEventRsvp: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let eventId: String
    let tierId: String
    let status: String
    let priceCentsPaid: Int
    /// What the door reads. Snapshot at claim time — a host editing the tier
    /// afterwards cannot silently invalidate a ticket already issued.
    let ticketCode: String
    let entryValidFrom: Date
    let entryValidUntil: Date
    let entryValidity: HostEventEntryValidity
    let showOnAttendeeList: Bool
    let createdAt: Date

    var isConfirmed: Bool { status == "confirmed" }
}

struct HostEventWaitlistEntry: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let tierId: String
    let state: HostEventWaitlistState
    let joinedAt: Date
    /// 1-based place in the queue. Join time only — nothing buys a better one.
    let position: Int
    let offeredAt: Date?
    let claimExpiresAt: Date?
    let claimable: Bool
}

struct HostEventAttendee: Codable, Identifiable, Hashable, Sendable {
    let userId: String
    let displayName: String
    let avatarUrl: String?
    let tierName: String
    /// True when this person opted out of the public list. Only the host ever
    /// sees such a row, and the UI must label it rather than silently show it.
    let hiddenFromPublic: Bool

    var id: String { userId }
}

struct HostEventAttendeeList: Codable, Sendable {
    let attendeeListPublic: Bool
    let viewerIsHost: Bool
    let count: Int
    let attendees: [HostEventAttendee]
}

// MARK: - Creation input

/// What the create screen collects for one tier before the event exists.
/// Kept separate from `HostEventTier` (which carries server-owned fields like
/// `remaining`) so a draft can never be mistaken for a live tier.
struct HostEventTierDraft: Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String = ""
    var quantity: Int = 100
    var salesStartAt: Date
    var salesEndAt: Date
    var entryValidFrom: Date
    var entryValidUntil: Date

    /// Mirrors `validateTierWindows` in host-event-rules.ts, so a bad window
    /// is caught before the round trip. The server re-checks regardless.
    var windowProblemKey: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "host.tier.error.name" }
        if quantity < 1 { return "host.tier.error.quantity" }
        if salesEndAt <= salesStartAt { return "host.tier.error.salesInverted" }
        if entryValidUntil <= entryValidFrom { return "host.tier.error.entryInverted" }
        if entryValidUntil <= salesStartAt { return "host.tier.error.entryBeforeSales" }
        return nil
    }
}

struct HostEventDraft: Sendable {
    var venueId: String
    var venueName: String
    var title: String
    var description: String
    var startsAt: Date
    var endsAt: Date?
    var attendeeListPublic: Bool
    var claimWindowMinutes: Int
    var publish: Bool
    var tiers: [HostEventTierDraft]
}

// MARK: - Formatting

/// One place that formats the two windows a host event lives by, so the
/// entry-validity line reads identically everywhere it appears — it is the
/// thing promoters actually sell ("free before 11").
enum HostEventFormat {
    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func dayAndTime(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    /// "10:00 PM – 11:00 PM", collapsing the day when both ends share one.
    static func window(_ from: Date, _ until: Date) -> String {
        let sameDay = Calendar.current.isDate(from, inSameDayAs: until)
        return sameDay
            ? "\(dayAndTime(from)) – \(time(until))"
            : "\(dayAndTime(from)) – \(dayAndTime(until))"
    }

    /// "12m left" for a claim window that is ticking. nil once it has passed.
    static func countdown(to date: Date, now: Date = Date()) -> String? {
        let seconds = Int(date.timeIntervalSince(now))
        guard seconds > 0 else { return nil }
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "\(seconds / 3600)h \((seconds % 3600) / 60)m"
    }
}
