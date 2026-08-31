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

    /// The `convertFromSnakeCase` + `.iso8601` decoder every repository
    /// rebuilt locally.
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// The matching encoder, for the repositories that also rebuilt this.
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}
