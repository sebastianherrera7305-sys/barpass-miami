import Foundation

protocol PostRepository: Sendable {
    func posts(venueId: String) async throws -> [VenuePost]
    func create(_ post: VenuePost) async throws
    func delete(_ post: VenuePost) async throws
}

// MARK: - Local (disk) — offline-first store and fallback

actor LocalPostRepository: PostRepository {
    private let fileURL: URL
    private var cache: [VenuePost]?

    init() {
        // .first! crasheaba en cualquier sandbox donde applicationSupportDirectory
        // viniera vacío (raro, pero no imposible) — .temporaryDirectory siempre
        // existe y es un fallback seguro (los posts igual se re-sincronizan del
        // backend si se pierden).
        let base = (FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("BarPassPosts", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("posts.json")
    }

    private func all() -> [VenuePost] {
        if let cache { return cache }
        let posts = (try? Data(contentsOf: fileURL))
            .flatMap { try? JSONDecoder().decode([VenuePost].self, from: $0) } ?? []
        cache = posts
        return posts
    }

    func posts(venueId: String) async throws -> [VenuePost] {
        all().filter { $0.venueId == venueId }.sorted { $0.createdAt > $1.createdAt }
    }

    func create(_ post: VenuePost) async throws {
        var posts = all()
        posts.removeAll { $0.id == post.id }
        posts.insert(post, at: 0)
        try write(posts)
    }

    func delete(_ post: VenuePost) async throws {
        var posts = all()
        posts.removeAll { $0.id == post.id }
        try write(posts)
    }

    private func write(_ posts: [VenuePost]) throws {
        cache = posts
        try JSONEncoder().encode(posts).write(to: fileURL, options: .atomic)
    }
}

// MARK: - Supabase (venue_posts) with local-first behavior

/// Reads merge remote + locally-pending posts; writes save locally FIRST
/// (never lose a post), then try the backend. Posts written while logged
/// out or before the `venue_posts` table exists stay local with
/// `pendingSync = true`.
actor SupabasePostRepository: PostRepository {
    private let local = LocalPostRepository()

    private struct Row: Codable {
        let id: UUID
        let venueId: UUID
        let userId: UUID?
        let authorHandle: String
        let caption: String
        let emoji: String?
        let vibeRating: Int?
        let drinksRating: Int?
        let musicRating: Int?
        let createdAt: Date
    }

    func posts(venueId: String) async throws -> [VenuePost] {
        let localPosts = (try? await local.posts(venueId: venueId)) ?? []
        guard let remote = try? await fetchRemote(venueId: venueId) else {
            return localPosts   // offline / table missing → local only
        }
        let remoteIds = Set(remote.map(\.id))
        let pendingOnly = localPosts.filter { !remoteIds.contains($0.id) }
        return (remote + pendingOnly).sorted { $0.createdAt > $1.createdAt }
    }

    func create(_ post: VenuePost) async throws {
        // Local first — the post is never lost.
        var p = post
        p.pendingSync = true
        try await local.create(p)

        guard let session = AuthService.shared.restoreSession() else { return }
        var body: [String: Any] = [
            "id": p.id.lowercased(),
            "venue_id": p.venueId.lowercased(),
            "user_id": session.user.id,
            "author_handle": p.authorHandle,
            "caption": p.caption,
        ]
        if let e = p.emoji { body["emoji"] = e }
        if let r = p.vibeRating { body["vibe_rating"] = r }
        if let r = p.drinksRating { body["drinks_rating"] = r }
        if let r = p.musicRating { body["music_rating"] = r }

        let request = try SupabaseRESTClient.request(
            "POST", path: "venue_posts",
            body: try JSONSerialization.data(withJSONObject: body),
            accessToken: session.accessToken,
            extraHeaders: ["Prefer": "return=minimal"]
        )
        if (try? await SupabaseRESTClient.send(request)) != nil {
            p.pendingSync = false
            try await local.create(p)   // mark synced
        }
    }

    func delete(_ post: VenuePost) async throws {
        try? await local.delete(post)
        guard let session = AuthService.shared.restoreSession() else { return }
        let request = try SupabaseRESTClient.request(
            "DELETE", path: "venue_posts",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(post.id.lowercased())")],
            accessToken: session.accessToken
        )
        try? await SupabaseRESTClient.send(request)
    }

    private func fetchRemote(venueId: String) async throws -> [VenuePost] {
        // Anon key doubles as bearer here — venue_posts reads are public
        // (RLS: "to anon, authenticated using (true)"), same as StadiumRepository.
        let request = try SupabaseRESTClient.request(
            "GET", path: "venue_posts",
            queryItems: [
                URLQueryItem(name: "venue_id", value: "eq.\(venueId.lowercased())"),
                URLQueryItem(name: "order", value: "created_at.desc"),
                URLQueryItem(name: "limit", value: "50"),
            ],
            accessToken: SupabaseRESTClient.anonKey,
            timeout: 8
        )
        let data = try await SupabaseRESTClient.send(request)
        return try SupabaseRESTClient.decoder.decode([Row].self, from: data).map {
            VenuePost(id: $0.id.uuidString.lowercased(),
                      venueId: $0.venueId.uuidString.lowercased(),
                      userId: $0.userId?.uuidString.lowercased(),
                      authorHandle: $0.authorHandle,
                      caption: $0.caption,
                      emoji: $0.emoji,
                      vibeRating: $0.vibeRating,
                      drinksRating: $0.drinksRating,
                      musicRating: $0.musicRating,
                      createdAt: $0.createdAt,
                      pendingSync: false)
        }
    }
}
