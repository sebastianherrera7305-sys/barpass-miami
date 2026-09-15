import Foundation

/// Shared request-building/auth/status-check boilerplate that was
/// copy-pasted, nearly verbatim, across a dozen Supabase-backed
/// repositories (`freshSession()` alone was identical in 5+ files).
/// Decoding stays with each repository — bare arrays, bare scalars, RPC
/// error payloads, and custom error mapping differ too much between them
/// to hide behind one generic helper here.
enum SupabaseRESTClient {
    static let baseURL = SupabaseConfig.url.absoluteString
    static let anonKey = SupabaseConfig.anonKey

    /// Refreshes the cached session if its token is stale and returns it —
    /// or throws if there's no signed-in session at all. Every RLS-scoped
    /// repository needs this before building a request.
    static func freshSession() async throws -> AuthSession {
        guard await AuthService.shared.refreshIfNeeded(),
              let session = AuthService.shared.restoreSession() else {
            throw URLError(.userAuthenticationRequired)
        }
        return session
    }

    /// Builds a request against `.../rest/v1/{path}` — `path` can be a
    /// table name with query filters (`"venues?select=..."` already
    /// encoded, or pass `queryItems` instead) or an RPC call
    /// (`"rpc/send_chapter_message"`). `accessToken` is omitted for public,
    /// anon-key-only reads (e.g. venues, stadiums); pass it for anything
    /// RLS-scoped to `auth.uid()`.
    static func request(
        _ method: String,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        accessToken: String? = nil,
        extraHeaders: [String: String] = [:],
        timeout: TimeInterval? = nil
    ) throws -> URLRequest {
        var components = URLComponents(string: "\(baseURL)/rest/v1/\(path)")
        if !queryItems.isEmpty { components?.queryItems = queryItems }
        guard let url = components?.url else { throw URLError(.badURL) }

        var req = URLRequest(url: url)
        req.httpMethod = method
        if let timeout { req.timeoutInterval = timeout }
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        if let accessToken { req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        for (key, value) in extraHeaders { req.setValue(value, forHTTPHeaderField: key) }
        req.httpBody = body
        return req
    }

    /// Executes and status-checks; returns the raw response data for the
    /// caller to decode. Throws `URLError(.badServerResponse)` on any
    /// non-2xx — callers that need the response body to map a domain error
    /// (e.g. `VenueCheckinError`) should use `URLSession.shared.data(for:)`
    /// directly instead, same as before.
    @discardableResult
    static func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    /// The `convertFromSnakeCase` + ISO-8601 decoder every repository
    /// rebuilt locally.
    ///
    /// The date strategy is NOT plain `.iso8601`. Postgres renders a
    /// `timestamptz` with however many fractional digits the value
    /// actually has — `…:45+00:00` when it lands on a whole second and
    /// `…:45.123456+00:00` the rest of the time — and `.iso8601` throws on
    /// the second form. Every repository reading a row with a `now()`
    /// default was therefore one microsecond away from decoding nothing,
    /// which surfaces as an empty list rather than an error because the
    /// call sites use `try?`. `HostEventCoding` already carried this fix
    /// locally; this is the same tolerance for the PostgREST path.
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = parseTimestamp(raw) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(raw)")
        }
        return d
    }()

    // Shared, not per-call. `ISO8601DateFormatter` is not `Sendable`, but
    // parsing on it is thread-safe and it is only ever read here. Building
    // one per decode is the mistake that froze build 63: a catalogue load
    // decodes two timestamps on each of ~1,800 venues, and that is 3,600
    // formatter allocations on whatever thread got there first.
    nonisolated(unsafe) private static let fractionalFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) private static let plainFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Tries fractional, then plain, then plain with the fraction cut out —
    /// the last one covers the 6-digit microsecond precision Postgres emits,
    /// which `ISO8601DateFormatter` does not reliably accept even with
    /// `.withFractionalSeconds`.
    static func parseTimestamp(_ raw: String) -> Date? {
        if let date = fractionalFormatter.date(from: raw) { return date }
        if let date = plainFormatter.date(from: raw) { return date }
        guard let dot = raw.firstIndex(of: ".") else { return nil }
        let tail = raw[dot...].drop(while: { $0.isNumber || $0 == "." })
        return plainFormatter.date(from: String(raw[raw.startIndex..<dot]) + tail)
    }

    /// The matching encoder, for the repositories that also rebuilt this.
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}
