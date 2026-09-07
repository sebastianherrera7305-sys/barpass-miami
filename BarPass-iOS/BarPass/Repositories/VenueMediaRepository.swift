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

enum VenueMediaError: LocalizedError {
    case emptyFile
    case compressionFailed
    case server(String)

    var errorDescription: String? {
        switch self {
        case .emptyFile: return "Empty file"
        case .compressionFailed: return "Couldn't compress the video"
        case .server(let body): return body
        }
    }
}

protocol VenueMediaRepository: Sendable {
    func media(for venueId: String) async throws -> [VenueMediaItem]
    /// Uploads an already-compressed local file to Supabase Storage in
    /// resumable chunks, then inserts the row pointing at it.
    /// `fileExtension` has no leading dot ("jpg", "mp4"). `progress` is
    /// called with 0…1 as chunks land.
    func upload(
        venueId: String,
        fileURL: URL,
        mediaType: VenueMediaType,
        contentType: String,
        fileExtension: String,
        progress: @MainActor @Sendable (Double) -> Void
    ) async throws -> VenueMediaItem
    func delete(_ id: String) async throws
}

/// "Factory Town" (an event venue open only a handful of nights a year) is
/// the trigger — the user wants people at tonight's event posting
/// photos/videos from inside the app. Deliberately simple for a same-day
/// ship (supabase/venue_media.sql): no moderation queue, public read,
/// delete-your-own only.
///
/// Upload goes through Supabase's resumable (TUS) endpoint in 6MB chunks
/// rather than one POST — verified 2026-09-06: a single-shot POST of a raw
/// phone video (100-400MB) dies against the project's 50MB object cap and,
/// on venue LTE, a single multi-minute request drops long before that. The
/// caller compresses first (VideoCompressor / ImageDownscaler in
/// VenueMediaSection.swift); chunking makes the remaining tens of MB survive
/// a flaky connection and lets us show real progress.
actor SupabaseVenueMediaRepository: VenueMediaRepository {
    private static let bucket = "venue-media"
    /// Supabase's TUS server requires exactly 6MB chunks (except the last).
    private static let chunkSize = 6 * 1024 * 1024
    /// A 6MB chunk on ~1 Mbps venue LTE takes ~50s; the default 60s
    /// no-data timeout is too tight for that.
    private static let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 180
        return URLSession(configuration: config)
    }()

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

    func upload(
        venueId: String,
        fileURL: URL,
        mediaType: VenueMediaType,
        contentType: String,
        fileExtension: String,
        progress: @MainActor @Sendable (Double) -> Void
    ) async throws -> VenueMediaItem {
        let session = try await SupabaseRESTClient.freshSession()
        // Storage RLS (venue_media.sql) requires the path's first segment
        // to equal the caller's own auth.uid() — that's what stops one
        // user from overwriting or guessing another's upload path.
        let path = "\(session.user.id)/\(UUID().uuidString).\(fileExtension)"

        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let total = (attrs[.size] as? NSNumber)?.intValue ?? 0
        guard total > 0 else { throw VenueMediaError.emptyFile }

        func b64(_ s: String) -> String { Data(s.utf8).base64EncodedString() }
        let authHeaders = [
            "apikey": SupabaseRESTClient.anonKey,
            "Authorization": "Bearer \(session.accessToken)",
            "Tus-Resumable": "1.0.0",
        ]

        // 1. Create the upload — the Location header is the chunk target.
        guard let createURL = URL(string: "\(SupabaseRESTClient.baseURL)/storage/v1/upload/resumable") else {
            throw URLError(.badURL)
        }
        var create = URLRequest(url: createURL)
        create.httpMethod = "POST"
        authHeaders.forEach { create.setValue($1, forHTTPHeaderField: $0) }
        create.setValue(String(total), forHTTPHeaderField: "Upload-Length")
        create.setValue(
            "bucketName \(b64(Self.bucket)),objectName \(b64(path)),contentType \(b64(contentType))",
            forHTTPHeaderField: "Upload-Metadata"
        )
        create.setValue("true", forHTTPHeaderField: "x-upsert")
        let (createData, createResp) = try await Self.urlSession.data(for: create)
        guard let createHTTP = createResp as? HTTPURLResponse, 200..<300 ~= createHTTP.statusCode,
              let location = createHTTP.value(forHTTPHeaderField: "Location"),
              let uploadURL = URL(string: location, relativeTo: createURL) else {
            throw VenueMediaError.server(String(data: createData, encoding: .utf8) ?? "upload create failed")
        }

        // 2. PATCH the file in 6MB chunks, reading from disk as we go so a
        //    long video never sits in memory whole.
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var offset = 0
        while offset < total {
            try handle.seek(toOffset: UInt64(offset))
            guard let chunk = try handle.read(upToCount: Self.chunkSize), !chunk.isEmpty else { break }
            var patch = URLRequest(url: uploadURL)
            patch.httpMethod = "PATCH"
            authHeaders.forEach { patch.setValue($1, forHTTPHeaderField: $0) }
            patch.setValue(String(offset), forHTTPHeaderField: "Upload-Offset")
            patch.setValue("application/offset+octet-stream", forHTTPHeaderField: "Content-Type")
            let (patchData, patchResp) = try await Self.urlSession.upload(for: patch, from: chunk)
            guard let patchHTTP = patchResp as? HTTPURLResponse, 200..<300 ~= patchHTTP.statusCode else {
                throw VenueMediaError.server(String(data: patchData, encoding: .utf8) ?? "upload chunk failed")
            }
            offset = Int(patchHTTP.value(forHTTPHeaderField: "Upload-Offset") ?? "") ?? (offset + chunk.count)
            let fraction = Double(offset) / Double(total)
            await progress(fraction)
        }

        // 3. Row pointing at the public URL.
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
