import Foundation

struct ChapterEvent: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let description: String?
    let locationName: String?
    let startsAt: Date
    let endsAt: Date?
    let createdBy: String
    let createdAt: Date
    let rsvpCount: Int
    let going: Bool
    let isPublic: Bool
}

/// A chapter event another chapter (or any student at the same university)
/// opted to publish campus-wide — see list_university_public_events(). No
/// going/rsvpCount editing here; RSVPing stays a chapter-membership action
/// on the per-chapter screen, this is discovery only.
struct UniversityPublicEvent: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let description: String?
    let locationName: String?
    let startsAt: Date
    let endsAt: Date?
    let chapterId: String
    let chapterName: String
    let rsvpCount: Int
}

protocol ChapterEventsRepository: Sendable {
    func events() async throws -> [ChapterEvent]
    func create(title: String, description: String?, locationName: String?, startsAt: Date, endsAt: Date?, isPublic: Bool) async throws
    func delete(eventId: String) async throws
    /// Returns the fresh (going, rsvpCount) after toggling — the server is
    /// the source of truth for the count, never a client-side +1/-1.
    func toggleRSVP(eventId: String) async throws -> (going: Bool, rsvpCount: Int)
    func publicEvents(universityId: String) async throws -> [UniversityPublicEvent]
}

final actor SupabaseChapterEventsRepository: ChapterEventsRepository {
    func events() async throws -> [ChapterEvent] {
        let session = try await SupabaseRESTClient.freshSession()
        let request = try SupabaseRESTClient.request(
            "POST", path: "rpc/list_chapter_events", body: Data("{}".utf8), accessToken: session.accessToken
        )
        let data = try await SupabaseRESTClient.send(request)
        return try SupabaseRESTClient.decoder.decode([ChapterEvent].self, from: data)
    }

    /// Affiliation, ban, rate-limit, and date sanity are all enforced
    /// server-side by create_chapter_event() — same trust boundary as
    /// send_chapter_message().
    func create(title: String, description: String?, locationName: String?, startsAt: Date, endsAt: Date?, isPublic: Bool) async throws {
        let session = try await SupabaseRESTClient.freshSession()
        var body: [String: Any] = [
            "p_title": title,
            "p_starts_at": ISO8601DateFormatter().string(from: startsAt),
            "p_is_public": isPublic,
        ]
        if let description { body["p_description"] = description }
        if let locationName { body["p_location_name"] = locationName }
        if let endsAt { body["p_ends_at"] = ISO8601DateFormatter().string(from: endsAt) }
        let data = try JSONSerialization.data(withJSONObject: body)
        let request = try SupabaseRESTClient.request(
            "POST", path: "rpc/create_chapter_event", body: data, accessToken: session.accessToken
        )
        do {
            try await SupabaseRESTClient.send(request)
        } catch {
            throw NSError(domain: "ChapterEvents", code: 0, userInfo: [NSLocalizedDescriptionKey: error.localizedDescription])
        }
    }

    func delete(eventId: String) async throws {
        let session = try await SupabaseRESTClient.freshSession()
        let body = try SupabaseRESTClient.encoder.encode(["p_event_id": eventId])
        let request = try SupabaseRESTClient.request(
            "POST", path: "rpc/delete_chapter_event", body: body, accessToken: session.accessToken
        )
        try await SupabaseRESTClient.send(request)
    }

    func toggleRSVP(eventId: String) async throws -> (going: Bool, rsvpCount: Int) {
        let session = try await SupabaseRESTClient.freshSession()
        let body = try SupabaseRESTClient.encoder.encode(["p_event_id": eventId])
        let request = try SupabaseRESTClient.request(
            "POST", path: "rpc/toggle_chapter_event_rsvp", body: body, accessToken: session.accessToken
        )
        let data = try await SupabaseRESTClient.send(request)
        struct Row: Codable { let going: Bool; let rsvpCount: Int }
        guard let row = try SupabaseRESTClient.decoder.decode([Row].self, from: data).first else {
            throw NSError(domain: "ChapterEvents", code: 1, userInfo: [NSLocalizedDescriptionKey: "empty response"])
        }
        return (row.going, row.rsvpCount)
    }

    func publicEvents(universityId: String) async throws -> [UniversityPublicEvent] {
        let session = try await SupabaseRESTClient.freshSession()
        let body = try SupabaseRESTClient.encoder.encode(["p_university_id": universityId])
        let request = try SupabaseRESTClient.request(
            "POST", path: "rpc/list_university_public_events", body: body, accessToken: session.accessToken
        )
        let data = try await SupabaseRESTClient.send(request)
        return try SupabaseRESTClient.decoder.decode([UniversityPublicEvent].self, from: data)
    }
}
