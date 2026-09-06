import Foundation

enum VenueMediaType: String, Codable {
    case photo, video
}

struct VenueMediaItem: Identifiable, Codable, Equatable {
    let id: String
    let venueId: String
    let userId: String
    let mediaUrl: String
    let mediaType: VenueMediaType
    let createdAt: Date
}

protocol VenueMediaRepository: Sendable {
    func media(for venueId: String) async throws -> [VenueMediaItem]
    /// Uploads the raw file to Supabase Storage, then inserts the row
    /// pointing at it. `fileExtension` has no leading dot ("jpg", "mov").
    func upload(venueId: String, data: Data, mediaType: VenueMediaType, fileExtension: String) async throws -> VenueMediaItem
    func delete(_ id: String) async throws
}

/// "Factory Town" (an event venue open only a handful of nights a year) is
/// the trigger — the user wants people at tonight's event posting
/// photos/videos from inside the app. Deliberately simple for a same-day
/// ship (supabase/venue_media.sql): no moderation queue, public read,
/// delete-your-own only.
actor SupabaseVenueMediaRepository: VenueMediaRepository {
    private static let bucket = "venue-media"

    func media(for venueId: String) async throws -> [VenueMediaItem] {
        let req = try SupabaseRESTClient.request(
            "GET", path: "venue_media",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "venue_id", value: "eq.\(venueId)"),
                URLQueryItem(name: "order", value: "created_at.desc"),
            ]
        )
        let data = try await SupabaseRESTClient.send(req)
        return try SupabaseRESTClient.decoder.decode([VenueMediaItem].self, from: data)
    }

    func upload(venueId: String, data: Data, mediaType: VenueMediaType, fileExtension: String) async throws -> VenueMediaItem {
        let session = try await SupabaseRESTClient.freshSession()
        // Storage RLS (venue_media.sql) requires the path's first segment
        // to equal the caller's own auth.uid() — that's what stops one
        // user from overwriting or guessing another's upload path.
        let path = "\(session.user.id)/\(UUID().uuidString).\(fileExtension)"
        guard let uploadURL = URL(string: "\(SupabaseRESTClient.baseURL)/storage/v1/object/\(Self.bucket)/\(path)") else {
            throw URLError(.badURL)
        }
        var uploadRequest = URLRequest(url: uploadURL)
        uploadRequest.httpMethod = "POST"
        uploadRequest.setValue(SupabaseRESTClient.anonKey, forHTTPHeaderField: "apikey")
        uploadRequest.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        uploadRequest.setValue(mediaType == .video ? "video/quicktime" : "image/jpeg", forHTTPHeaderField: "Content-Type")
        uploadRequest.httpBody = data
        let (uploadData, uploadResponse) = try await URLSession.shared.upload(for: uploadRequest, from: data)
        guard let http = uploadResponse as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: String(data: uploadData, encoding: .utf8) ?? "upload failed"])
        }

        let publicURL = "\(SupabaseRESTClient.baseURL)/storage/v1/object/public/\(Self.bucket)/\(path)"
        struct NewRow: Encodable {
            let venueId: String
            let userId: String
            let mediaUrl: String
            let mediaType: VenueMediaType
        }
        let body = try SupabaseRESTClient.encoder.encode(
            NewRow(venueId: venueId, userId: session.user.id, mediaUrl: publicURL, mediaType: mediaType)
        )
        let insertReq = try SupabaseRESTClient.request(
            "POST", path: "venue_media", body: body, accessToken: session.accessToken,
            extraHeaders: ["Prefer": "return=representation"]
        )
        let insertData = try await SupabaseRESTClient.send(insertReq)
        let rows = try SupabaseRESTClient.decoder.decode([VenueMediaItem].self, from: insertData)
        guard let row = rows.first else { throw URLError(.cannotParseResponse) }
        return row
    }

    func delete(_ id: String) async throws {
        let session = try await SupabaseRESTClient.freshSession()
        let req = try SupabaseRESTClient.request(
            "DELETE", path: "venue_media",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(id)")],
            accessToken: session.accessToken
        )
        try await SupabaseRESTClient.send(req)
    }
}
