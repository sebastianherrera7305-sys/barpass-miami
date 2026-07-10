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
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
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
    private static let supabaseURL = "https://hrhdezziddfrktvtgzbg.supabase.co"
    private static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhyaGRlenppZGRmcmt0dnRnemJnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMzODM1NjksImV4cCI6MjA5ODk1OTU2OX0.vzgIE7JPL8vN0fWVGkf-AvUCH1iWTioHjZpxcuSRBRo"

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

        var request = URLRequest(url: URL(string: "\(Self.supabaseURL)/rest/v1/venue_posts")!)
        request.httpMethod = "POST"
        request.setValue(Self.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode {
            p.pendingSync = false
            try await local.create(p)   // mark synced
        }
    }

    func delete(_ post: VenuePost) async throws {
        try? await local.delete(post)
        guard let session = AuthService.shared.restoreSession() else { return }
        var request = URLRequest(url: URL(string: "\(Self.supabaseURL)/rest/v1/venue_posts?id=eq.\(post.id.lowercased())")!)
        request.httpMethod = "DELETE"
        request.setValue(Self.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: request)
    }

    private func fetchRemote(venueId: String) async throws -> [VenuePost] {
        let url = URL(string: "\(Self.supabaseURL)/rest/v1/venue_posts?venue_id=eq.\(venueId.lowercased())&order=created_at.desc&limit=50")!
        var request = URLRequest(url: url)
        request.setValue(Self.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(Self.anonKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 8

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Row].self, from: data).map {
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
