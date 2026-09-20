import Foundation

/// A story is not a new kind of row. It is a `venue_media` row read inside
/// the night it was posted in — see supabase/venue_stories.sql. The night
/// ends at 6:00 AM in the VENUE's timezone, the same past-midnight rule
/// `VenueTimeStatus` uses for opening hours, because a photo taken at 2am
/// belongs to the evening that started the day before and an answer to
/// "where is everybody" from a previous night is worse than no answer.
///
/// What this type deliberately does NOT have is an author. `user_id` is
/// revoked from both `anon` and `authenticated` on the underlying table,
/// and `public.venue_stories` never selects it: knowing which named person
/// was inside which venue at 1am is location history, and the product only
/// ever needed a count. `posterSeq` is the honest middle — a number that
/// exists only within one venue on one night, so frames can be grouped by
/// the person who shot them without that person being identifiable, and so
/// one enthusiast posting ten times cannot inflate the crowd count.
struct VenueStory: Identifiable, Codable, Equatable, Sendable {
    /// Every readable column of the view, named explicitly. There is no
    /// `select=*` here or anywhere else that touches venue_media.
    static let columns = "id,venue_id,media_url,media_type,created_at,night_date,expires_at,poster_seq,is_mine"

    let id: String
    let venueId: String
    let mediaUrl: String
    let mediaType: VenueMediaType
    let createdAt: Date
    /// The night this belongs to, as the server computed it ("2026-09-12").
    /// A plain string: Postgres `date` is not a timestamp and must not be
    /// pushed through the ISO-8601 date strategy.
    let nightDate: String
    let expiresAt: Date
    /// Stable only within (venue, night). Restarts every night.
    let posterSeq: Int
    /// The one identity claim the server makes, and only ever about the
    /// caller themselves.
    let isMine: Bool
}

/// The crowd signal, and the whole product payoff: a venue card can say
/// "12 people posted from here tonight" without anyone learning who they
/// are. A count and a frame, never a roster.
struct VenueStoryPulse: Identifiable, Codable, Equatable, Sendable {
    static let columns = "venue_id,story_count,poster_count,latest_at,night_date,latest_media_url,latest_media_type"

    let venueId: String
    let storyCount: Int
    /// Distinct people, not frames.
    let posterCount: Int
    let latestAt: Date
    let nightDate: String
    let latestMediaUrl: String?
    let latestMediaType: VenueMediaType?

    var id: String { venueId }
}

protocol VenueStoryRepository: Sendable {
    /// Tonight's stories at one venue, oldest first — a story plays in the
    /// order the night happened.
    func stories(for venueId: String) async throws -> [VenueStory]
    /// Every venue with at least one live story, in one request. The view
    /// only ever contains the night in progress, so this stays small
    /// (zero rows most of the day) no matter how large the catalogue is.
    func pulse() async throws -> [VenueStoryPulse]
}

actor SupabaseVenueStoryRepository: VenueStoryRepository {

    /// Signed in when possible so the server can set `is_mine`; anonymous
    /// otherwise. A story is public content either way — there is nothing
    /// in the view that a session would unlock.
    private func accessToken() async -> String? {
        try? await SupabaseRESTClient.freshSession().accessToken
    }

    func stories(for venueId: String) async throws -> [VenueStory] {
        let req = try SupabaseRESTClient.request(
            "GET", path: "venue_stories",
            queryItems: [
                URLQueryItem(name: "select", value: VenueStory.columns),
                URLQueryItem(name: "venue_id", value: "eq.\(venueId)"),
                URLQueryItem(name: "order", value: "created_at.asc"),
            ],
            accessToken: await accessToken(),
            // Inside a club the LTE is contended to uselessness; a story
            // strip that never resolves is worse than one that gives up
            // and shows nothing.
            timeout: 12
        )
        let data = try await SupabaseRESTClient.send(req)
        let rows = try SupabaseRESTClient.decoder.decode([VenueStory].self, from: data)
        // El filtro va ACÁ y no en cada pantalla. La misma foto se dibuja en
        // tres lugares (el visor, la tira del venue, el rail de Social), y
        // "una línea en cada sitio de render" es una instrucción que alguien
        // se va a olvidar en el cuarto — y un ocultar que funciona en dos de
        // tres se lee como "no anduvo".
        return HiddenStories.filtered(rows) { $0.id }
    }

    func pulse() async throws -> [VenueStoryPulse] {
        let req = try SupabaseRESTClient.request(
            "GET", path: "venue_story_pulse",
            queryItems: [
                URLQueryItem(name: "select", value: VenueStoryPulse.columns),
                URLQueryItem(name: "order", value: "latest_at.desc"),
            ],
            timeout: 12
        )
        let data = try await SupabaseRESTClient.send(req)
        return try SupabaseRESTClient.decoder.decode([VenueStoryPulse].self, from: data)
    }
}

/// One shared, cheap answer to "does this venue have anything tonight",
/// read synchronously by every card in the feed.
///
/// The alternative — a request per card — is exactly the pattern that made
/// the Tonight feed unusable before (`Stop downloading 23 cities to show
/// one`). `venue_story_pulse` is the night in progress across the whole
/// catalogue, which is a handful of rows, so one request serves the entire
/// screen and every card reads a dictionary.
@MainActor
final class VenueStoryPulseStore: ObservableObject {
    static let shared = VenueStoryPulseStore()

    @Published private(set) var byVenue: [String: VenueStoryPulse] = [:]
    @Published private(set) var hasLoaded = false

    private let repository: VenueStoryRepository
    private var inFlight: Task<Void, Never>?
    private var lastLoad: Date?
    /// A night moves, but not every second. Frequent enough that a venue
    /// filling up shows within a few minutes, rare enough to cost nothing.
    private static let minInterval: TimeInterval = 120

    init(repository: VenueStoryRepository = RepositoryDependencies.venueStory) {
        self.repository = repository
    }

    func pulse(for venueId: String) -> VenueStoryPulse? { byVenue[venueId] }

    /// Safe to call from every `.task` on screen; collapses to one request.
    func refresh(force: Bool = false) {
        if !force, let lastLoad, Date().timeIntervalSince(lastLoad) < Self.minInterval { return }
        if inFlight != nil { return }
        inFlight = Task { [repository] in
            defer { inFlight = nil }
            guard let rows = try? await repository.pulse() else { return }
            lastLoad = Date()
            byVenue = Dictionary(rows.map { ($0.venueId, $0) }, uniquingKeysWith: { first, _ in first })
            hasLoaded = true
        }
    }

    /// After the user posts, so their own frame shows up on the card
    /// immediately rather than after the next interval.
    func invalidate() {
        lastLoad = nil
        refresh(force: true)
    }
}
