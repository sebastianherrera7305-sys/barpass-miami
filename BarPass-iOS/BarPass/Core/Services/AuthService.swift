import Foundation

// MARK: - Session models

struct AuthUser: Codable, Sendable {
    let id: String
    let email: String?
}

struct AuthSession: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let user: AuthUser

    var isExpired: Bool { Date() >= expiresAt }
}

// MARK: - Supabase Auth (native, via URLSession — no SDK)

/// Email/password auth against Supabase GoTrue REST. The session is cached
/// in UserDefaults so `restoreSession()` is synchronous and instant at launch.
final class AuthService: @unchecked Sendable {
    static let shared = AuthService()

    // URLSession is Sendable — a plain constant is concurrency-safe.
    private static let customSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = requestTimeout
        cfg.timeoutIntervalForResource = requestTimeout
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    private static let baseURL = "https://hrhdezziddfrktvtgzbg.supabase.co/auth/v1"
    private static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhyaGRlenppZGRmcmt0dnRnemJnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMzODM1NjksImV4cCI6MjA5ODk1OTU2OX0.vzgIE7JPL8vN0fWVGkf-AvUCH1iWTioHjZpxcuSRBRo"
    private static let sessionKey = "bp_auth_session"
    private static let requestTimeout: TimeInterval = 8

    private let defaults = UserDefaults.standard
    private let lock = NSLock()

    // MARK: Public API

    /// Synchronous — reads the cached session. Instant at launch.
    func restoreSession() -> AuthSession? {
        lock.lock(); defer { lock.unlock() }
        guard let data = defaults.data(forKey: Self.sessionKey),
              let session = try? JSONDecoder().decode(AuthSession.self, from: data)
        else { return nil }
        BPAnalytics.track(.sessionRestored)
        return session
    }

    @discardableResult
    func refreshIfNeeded() async -> Bool {
        guard let session = restoreSession(), session.isExpired else { return true }
        do {
            let refreshed = try await tokenRequest(
                grant: "refresh_token",
                body: ["refresh_token": session.refreshToken]
            )
            store(refreshed)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func signIn(email: String, password: String) async throws -> AuthSession {
        let session = try await tokenRequest(
            grant: "password",
            body: ["email": email, "password": password]
        )
        store(session)
        BPAnalytics.track(.signIn(method: "email", duration: 0))
        return session
    }

    @discardableResult
    func signUp(email: String, password: String) async throws -> AuthSession {
        var request = URLRequest(url: URL(string: "\(Self.baseURL)/signup")!)
        request.httpMethod = "POST"
        applyHeaders(&request)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])

        let (data, response) = try await Self.customSession.data(for: request)
        try Self.ensureOK(response, data: data)
        // Signup with autoconfirm returns a session; otherwise sign in directly.
        if let session = Self.parseSession(data) {
            store(session)
            BPAnalytics.track(.signUp(method: "email", duration: 0))
            return session
        }
        return try await signIn(email: email, password: password)
    }

    /// Exchanges an Apple identity token for a Supabase session via the
    /// `id_token` grant. `nonce` is the raw (unhashed) value whose SHA-256
    /// digest was sent to Apple in the original authorization request —
    /// Supabase re-hashes it server-side to verify the token wasn't replayed.
    @discardableResult
    func signInWithApple(idToken: String, nonce: String) async throws -> AuthSession {
        let session = try await tokenRequest(
            grant: "id_token",
            body: ["provider": "apple", "id_token": idToken, "nonce": nonce]
        )
        store(session)
        BPAnalytics.track(.signIn(method: "apple", duration: 0))
        return session
    }

    func sendPasswordReset(email: String) async throws {
        var request = URLRequest(url: URL(string: "\(Self.baseURL)/recover")!)
        request.httpMethod = "POST"
        applyHeaders(&request)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email])
        let (data, response) = try await Self.customSession.data(for: request)
        try Self.ensureOK(response, data: data)
        BPAnalytics.track(.forgotPassword)
    }

    func signOut() {
        lock.lock(); defer { lock.unlock() }
        defaults.removeObject(forKey: Self.sessionKey)
    }

    // MARK: Internals

    private func tokenRequest(grant: String, body: [String: String]) async throws -> AuthSession {
        var request = URLRequest(url: URL(string: "\(Self.baseURL)/token?grant_type=\(grant)")!)
        request.httpMethod = "POST"
        applyHeaders(&request)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await Self.customSession.data(for: request)
        try Self.ensureOK(response, data: data)
        guard let session = Self.parseSession(data) else { throw AuthError.network }
        return session
    }

    private func applyHeaders(_ request: inout URLRequest) {
        request.setValue(Self.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = Self.requestTimeout
    }

    private static func ensureOK(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw AuthError.network }
        guard 200..<300 ~= http.statusCode else {
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let msg = (obj?["error_description"] ?? obj?["msg"] ?? obj?["message"]) as? String
            throw AuthError.badCredentials(msg ?? "Credenciales inválidas (\(http.statusCode)).")
        }
    }

    private static func parseSession(_ data: Data) -> AuthSession? {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let access = obj["access_token"] as? String,
              let refresh = obj["refresh_token"] as? String,
              let userObj = obj["user"] as? [String: Any],
              let uid = userObj["id"] as? String
        else { return nil }
        let expiresIn = (obj["expires_in"] as? Double) ?? 3600
        return AuthSession(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: Date().addingTimeInterval(expiresIn - 60),
            user: AuthUser(id: uid, email: userObj["email"] as? String)
        )
    }

    private func store(_ session: AuthSession) {
        lock.lock(); defer { lock.unlock() }
        if let data = try? JSONEncoder().encode(session) {
            defaults.set(data, forKey: Self.sessionKey)
        }
    }
}

enum AuthError: LocalizedError {
    case badCredentials(String)
    case network

    var errorDescription: String? {
        switch self {
        case .badCredentials(let msg): return msg
        case .network: return "No se pudo conectar. Revisa tu internet."
        }
    }
}
