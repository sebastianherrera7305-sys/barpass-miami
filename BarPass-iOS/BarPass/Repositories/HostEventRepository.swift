import Foundation

/// Host events — "let a promoter actually run a night through BarPass".
///
/// Unlike most repositories here, this one does NOT talk to Supabase REST for
/// its writes. Every mutation is a SECURITY DEFINER RPC behind our own Next.js
/// routes (`/api/host-events/*`), which hold the row locks that make a capped
/// free RSVP race-safe and the rate limits that keep the catalogue curated.
/// Going straight to PostgREST would bypass both, so it doesn't.
///
/// The one exception is `hostedEvents()`: the API has no "my events" listing
/// (GET /api/host-events is the public, published-only feed), and a host must
/// be able to find their own DRAFT. That is a plain RLS-scoped read — the
/// `hosts read own host events` policy already scopes it to auth.uid() — so it
/// goes through SupabaseRESTClient like any other read.
protocol HostEventRepository: Sendable {
    /// Published, upcoming events. `venueId` nil = everywhere.
    func events(venueId: String?, limit: Int) async throws -> [HostEvent]
    /// Everything the signed-in user hosts, drafts and cancelled included.
    func hostedEvents() async throws -> [HostEvent]
    func detail(eventId: String) async throws -> HostEventDetail
    func create(_ draft: HostEventDraft) async throws -> HostEventDetail
    func update(eventId: String, patch: HostEventPatch) async throws -> HostEvent

    func myRsvps(eventId: String) async throws -> [HostEventRsvp]
    func rsvp(eventId: String, tierId: String) async throws -> HostEventRsvp
    func releaseRsvp(eventId: String, rsvpId: String) async throws
    func setRsvpVisibility(eventId: String, rsvpId: String, visible: Bool) async throws -> HostEventRsvp

    func waitlist(eventId: String) async throws -> [HostEventWaitlistEntry]
    func joinWaitlist(eventId: String, tierId: String) async throws -> HostEventWaitlistEntry
    func leaveWaitlist(eventId: String, tierId: String) async throws
    func claimOffer(eventId: String, waitlistId: String) async throws -> HostEventRsvp

    func attendees(eventId: String) async throws -> HostEventAttendeeList
}

/// Only the fields a host may actually change. `venueId` and `hostId` are
/// absent on purpose — a database trigger pins both for the row's lifetime,
/// so offering them here would only invite a silently-ignored edit.
struct HostEventPatch: Encodable, Sendable {
    var title: String?
    var description: String?
    var startsAt: Date?
    var endsAt: Date?
    var status: String?
    var attendeeListPublic: Bool?
    var claimWindowMinutes: Int?
}

/// The server's `{error, message, retryable}` shape, narrowed to codes this
/// app can phrase itself. `message` is deliberately NOT shown: `rpcError()`
/// echoes raw Postgres text, which can carry table and constraint names.
struct HostEventError: LocalizedError, Sendable {
    let code: String
    let retryable: Bool

    var errorDescription: String? {
        let key = HostEventError.messageKeys[code] ?? "host.error.generic"
        return L10n.tSync(key)
    }

    private static let messageKeys: [String: String] = [
        "event_not_found": "host.error.eventNotFound",
        "tier_not_found": "host.error.tierNotFound",
        "event_not_published": "host.error.notPublished",
        "event_cancelled": "host.error.cancelled",
        "sales_not_open": "host.error.salesNotOpen",
        "sales_closed": "host.error.salesClosed",
        "paid_tier_not_enabled": "host.error.paidNotEnabled",
        "already_rsvped": "host.error.alreadyRsvped",
        "already_waitlisted": "host.error.alreadyWaitlisted",
        "sold_out": "host.error.soldOut",
        "not_sold_out": "host.error.notSoldOut",
        "rsvp_not_found": "host.error.rsvpNotFound",
        "rsvp_not_confirmed": "host.error.rsvpNotConfirmed",
        "waitlist_entry_not_found": "host.error.waitlistNotFound",
        "offer_not_found": "host.error.offerNotFound",
        "offer_expired": "host.error.offerExpired",
        "attendee_list_private": "host.error.listPrivate",
        "venue_not_found": "host.error.venueNotFound",
        "venue_not_bookable": "host.error.venueNotBookable",
        "invalid_tier_window": "host.error.invalidWindow",
        "invalid_payload": "host.error.invalidPayload",
        "rate_limited": "host.error.rateLimited",
        "backend_not_configured": "host.error.backendDown",
    ]
}

final actor BarPassHostEventRepository: HostEventRepository {

    // MARK: - Reads

    func events(venueId: String?, limit: Int) async throws -> [HostEvent] {
        var items = [URLQueryItem(name: "limit", value: String(limit))]
        if let venueId { items.append(URLQueryItem(name: "venueId", value: venueId)) }
        struct Response: Decodable { let events: [HostEvent] }
        return try await send(Response.self, "GET", "host-events", query: items, authenticated: false).events
    }

    func hostedEvents() async throws -> [HostEvent] {
        let session = try await SupabaseRESTClient.freshSession()
        let request = try SupabaseRESTClient.request(
            "GET", path: "host_events",
            queryItems: [
                // The embed is what gives the card a venue name without a
                // second round trip; venues are anon-readable already.
                URLQueryItem(name: "select", value: "*,venues(name,slug)"),
                URLQueryItem(name: "host_id", value: "eq.\(session.user.id)"),
                URLQueryItem(name: "order", value: "starts_at.desc"),
            ],
            accessToken: session.accessToken
        )
        let data = try await SupabaseRESTClient.send(request)
        return try HostEventRow.decoder.decode([HostEventRow].self, from: data).map(\.event)
    }

    func detail(eventId: String) async throws -> HostEventDetail {
        struct Response: Decodable {
            let event: HostEvent
            let tiers: [HostEventTier]
            let paidTiersEnabled: Bool
        }
        // Authenticated even for a published event: a host opening their own
        // DRAFT gets a 404 without a token.
        let r = try await send(Response.self, "GET", "host-events/\(eventId)")
        return HostEventDetail(event: r.event, tiers: r.tiers, paidTiersEnabled: r.paidTiersEnabled)
    }

    func attendees(eventId: String) async throws -> HostEventAttendeeList {
        try await send(HostEventAttendeeList.self, "GET", "host-events/\(eventId)/attendees")
    }

    // MARK: - Host writes

    func create(_ draft: HostEventDraft) async throws -> HostEventDetail {
        struct TierBody: Encodable {
            let name: String
            let priceCents: Int
            let quantity: Int
            let salesStartAt: Date
            let salesEndAt: Date
            let entryValidFrom: Date
            let entryValidUntil: Date
            let sortOrder: Int
        }
        struct Body: Encodable {
            let venueId: String
            let title: String
            let description: String
            let startsAt: Date
            let endsAt: Date?
            let attendeeListPublic: Bool
            let claimWindowMinutes: Int
            let publish: Bool
            let tiers: [TierBody]
        }
        let body = Body(
            venueId: draft.venueId,
            title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: draft.description,
            startsAt: draft.startsAt,
            endsAt: draft.endsAt,
            attendeeListPublic: draft.attendeeListPublic,
            claimWindowMinutes: draft.claimWindowMinutes,
            publish: draft.publish,
            tiers: draft.tiers.enumerated().map { index, t in
                TierBody(
                    name: t.name.trimmingCharacters(in: .whitespacesAndNewlines),
                    // Free only, today and by design: nothing can be charged
                    // while the Stripe account has charges disabled.
                    priceCents: 0,
                    quantity: t.quantity,
                    salesStartAt: t.salesStartAt, salesEndAt: t.salesEndAt,
                    entryValidFrom: t.entryValidFrom, entryValidUntil: t.entryValidUntil,
                    sortOrder: index
                )
            }
        )
        struct Response: Decodable {
            let event: HostEvent
            let tiers: [HostEventTier]
            let paidTiersEnabled: Bool
        }
        let r = try await send(Response.self, "POST", "host-events", body: body)
        return HostEventDetail(event: r.event, tiers: r.tiers, paidTiersEnabled: r.paidTiersEnabled)
    }

    func update(eventId: String, patch: HostEventPatch) async throws -> HostEvent {
        struct Response: Decodable { let event: HostEvent }
        return try await send(Response.self, "PATCH", "host-events/\(eventId)", body: patch).event
    }

    // MARK: - Attendee writes

    func myRsvps(eventId: String) async throws -> [HostEventRsvp] {
        struct Response: Decodable { let rsvps: [HostEventRsvp] }
        return try await send(Response.self, "GET", "host-events/\(eventId)/rsvp").rsvps
    }

    func rsvp(eventId: String, tierId: String) async throws -> HostEventRsvp {
        struct Body: Encodable { let tierId: String }
        struct Response: Decodable { let rsvp: HostEventRsvp }
        return try await send(Response.self, "POST", "host-events/\(eventId)/rsvp",
                              body: Body(tierId: tierId)).rsvp
    }

    func releaseRsvp(eventId: String, rsvpId: String) async throws {
        struct Response: Decodable { let releasedToWaitlist: Bool }
        // Query string rather than a DELETE body: URLSession is one of the
        // clients the route documents as awkward with the latter.
        _ = try await send(Response.self, "DELETE", "host-events/\(eventId)/rsvp",
                           query: [URLQueryItem(name: "rsvpId", value: rsvpId)])
    }

    func setRsvpVisibility(eventId: String, rsvpId: String, visible: Bool) async throws -> HostEventRsvp {
        struct Body: Encodable { let rsvpId: String; let showOnAttendeeList: Bool }
        struct Response: Decodable { let rsvp: HostEventRsvp }
        return try await send(Response.self, "PATCH", "host-events/\(eventId)/rsvp",
                              body: Body(rsvpId: rsvpId, showOnAttendeeList: visible)).rsvp
    }

    func waitlist(eventId: String) async throws -> [HostEventWaitlistEntry] {
        struct Response: Decodable { let entries: [HostEventWaitlistEntry] }
        return try await send(Response.self, "GET", "host-events/\(eventId)/waitlist").entries
    }

    func joinWaitlist(eventId: String, tierId: String) async throws -> HostEventWaitlistEntry {
        struct Body: Encodable { let tierId: String }
        struct Response: Decodable { let entry: HostEventWaitlistEntry }
        return try await send(Response.self, "POST", "host-events/\(eventId)/waitlist",
                              body: Body(tierId: tierId)).entry
    }

    func leaveWaitlist(eventId: String, tierId: String) async throws {
        struct Response: Decodable { let ok: Bool }
        _ = try await send(Response.self, "DELETE", "host-events/\(eventId)/waitlist",
                           query: [URLQueryItem(name: "tierId", value: tierId)])
    }

    func claimOffer(eventId: String, waitlistId: String) async throws -> HostEventRsvp {
        struct Body: Encodable { let waitlistId: String }
        struct Response: Decodable { let rsvp: HostEventRsvp }
        return try await send(Response.self, "POST", "host-events/\(eventId)/waitlist/claim",
                              body: Body(waitlistId: waitlistId)).rsvp
    }

    // MARK: - Transport

    private func send<T: Decodable>(
        _ type: T.Type,
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        body: (any Encodable)? = nil,
        authenticated: Bool = true
    ) async throws -> T {
        var components = URLComponents(
            url: APIClient.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authenticated {
            // freshSession() refreshes a stale JWT first — these routes read
            // the Bearer token, and the token lives ~59 minutes.
            let session = try await SupabaseRESTClient.freshSession()
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try HostEventCoding.encoder.encode(AnyEncodable(body))
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard 200..<300 ~= http.statusCode else {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            throw HostEventError(
                code: (json["error"] as? String) ?? "unknown",
                retryable: (json["retryable"] as? Bool) ?? false
            )
        }
        return try HostEventCoding.decoder.decode(T.self, from: data)
    }
}

/// Lets `send` take a heterogeneous body without a generic parameter that
/// every call site would have to spell out.
private struct AnyEncodable: Encodable {
    private let encodeTo: (Encoder) throws -> Void
    init(_ wrapped: any Encodable) { encodeTo = wrapped.encode(to:) }
    func encode(to encoder: Encoder) throws { try encodeTo(encoder) }
}

/// The API speaks camelCase (it is our own Next.js layer, not PostgREST), so
/// these deliberately do NOT convert case — unlike `SupabaseRESTClient`'s.
enum HostEventCoding {
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        // Postgres timestamptz comes back with fractional seconds sometimes
        // and without others; `.iso8601` alone throws on the former.
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = HostEventCoding.parse(string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(string)")
        }
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601   // z.iso.datetime() on the server
        return e
    }()

    static func parse(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}

/// The raw `host_events` row, for the one read that goes straight to
/// PostgREST. Mapped into the same `HostEvent` the API returns so no view
/// ever has to know which path a given event arrived by.
private struct HostEventRow: Decodable {
    struct VenueRef: Decodable { let name: String?; let slug: String? }
    let id: String
    let hostId: String
    let venueId: String
    let title: String
    let description: String
    let startsAt: Date
    let endsAt: Date?
    let status: HostEventStatus
    let attendeeListPublic: Bool
    let claimWindowMinutes: Int
    let coverImageUrl: String?
    let cancelledAt: Date?
    let createdAt: Date
    let venues: VenueRef?

    var event: HostEvent {
        HostEvent(
            id: id, hostId: hostId,
            venue: HostEventVenueRef(id: venueId, name: venues?.name, slug: venues?.slug),
            title: title, description: description, startsAt: startsAt, endsAt: endsAt,
            status: status, attendeeListPublic: attendeeListPublic,
            claimWindowMinutes: claimWindowMinutes, coverImageUrl: coverImageUrl,
            cancelledAt: cancelledAt, createdAt: createdAt)
    }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = HostEventCoding.parse(string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(string)")
        }
        return d
    }()
}
