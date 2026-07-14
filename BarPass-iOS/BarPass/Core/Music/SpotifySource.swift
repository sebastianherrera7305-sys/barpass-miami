import Foundation
import AuthenticationServices
import CryptoKit

/// Configuración de Spotify. Crear app gratis en developer.spotify.com,
/// agregar redirect URI `barpass://spotify-callback` y pegar el Client ID.
enum SpotifyConfig {
    static let clientID = "cd8eacb94ab34679a7c8f3484b4e803d"
    static let redirectURI = "barpass://spotify-callback"
    static let scopes = "user-top-read"
}

/// Adaptador Spotify — OAuth PKCE (sin client secret) + top artists.
/// Segundo proveedor de la capa MusicSource: demuestra que la abstracción
/// multi-proveedor funciona de verdad.
final class SpotifySource: NSObject, MusicSource, @unchecked Sendable {
    let kind: MusicSourceKind = .spotify

    private static let tokenKey = "bp_spotify_token"

    private struct Token: Codable {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Date
        var isExpired: Bool { Date() >= expiresAt }
    }

    // MARK: - Authorization (PKCE)

    @MainActor
    func requestAuthorization() async -> MusicAuthStatus {
        guard !SpotifyConfig.clientID.isEmpty else { return .notEntitled }
        if loadToken() != nil { return .authorized }

        // PKCE
        let verifier = Self.randomVerifier()
        let challenge = Self.codeChallenge(verifier)

        var comps = URLComponents(string: "https://accounts.spotify.com/authorize")!
        comps.queryItems = [
            .init(name: "client_id", value: SpotifyConfig.clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: SpotifyConfig.redirectURI),
            .init(name: "scope", value: SpotifyConfig.scopes),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: challenge),
        ]

        guard let callbackURL = await presentAuth(url: comps.url!) else { return .denied }
        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else { return .denied }

        do {
            try await exchangeCode(code, verifier: verifier)
            return .authorized
        } catch {
            return .denied
        }
    }

    @MainActor
    private func presentAuth(url: URL) async -> URL? {
        await withCheckedContinuation { cont in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: "barpass"
            ) { callbackURL, _ in
                cont.resume(returning: callbackURL)
            }
            session.presentationContextProvider = PresentationAnchor.shared
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }

    private func exchangeCode(_ code: String, verifier: String) async throws {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = [
            "grant_type=authorization_code",
            "code=\(code)",
            "redirect_uri=\(SpotifyConfig.redirectURI)",
            "client_id=\(SpotifyConfig.clientID)",
            "code_verifier=\(verifier)",
        ].joined(separator: "&").data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        try storeTokenResponse(data)
    }

    private func refreshIfNeeded() async throws -> String {
        guard let token = loadToken() else { throw MusicSourceError.notAuthorized }
        if !token.isExpired { return token.accessToken }
        guard let refresh = token.refreshToken else { throw MusicSourceError.notAuthorized }

        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = [
            "grant_type=refresh_token",
            "refresh_token=\(refresh)",
            "client_id=\(SpotifyConfig.clientID)",
        ].joined(separator: "&").data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        try storeTokenResponse(data, fallbackRefresh: refresh)
        guard let t = loadToken() else { throw MusicSourceError.notAuthorized }
        return t.accessToken
    }

    private func storeTokenResponse(_ data: Data, fallbackRefresh: String? = nil) throws {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let access = obj["access_token"] as? String else {
            throw MusicSourceError.network("token exchange failed")
        }
        let expiresIn = (obj["expires_in"] as? Double) ?? 3600
        let token = Token(
            accessToken: access,
            refreshToken: (obj["refresh_token"] as? String) ?? fallbackRefresh,
            expiresAt: Date().addingTimeInterval(expiresIn - 60)
        )
        if let d = try? JSONEncoder().encode(token) {
            UserDefaults.standard.set(d, forKey: Self.tokenKey)
        }
    }

    private func loadToken() -> Token? {
        UserDefaults.standard.data(forKey: Self.tokenKey)
            .flatMap { try? JSONDecoder().decode(Token.self, from: $0) }
    }

    // MARK: - Snapshot

    func snapshot(days: Int) async throws -> MusicSnapshot {
        guard !SpotifyConfig.clientID.isEmpty else { throw MusicSourceError.notEntitled }
        let access = try await refreshIfNeeded()

        // short_term ≈ últimas 4 semanas — lo más cercano a "esta semana" que da la API.
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/top/artists?time_range=short_term&limit=20")!)
        request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MusicSourceError.network("no response") }
        if http.statusCode == 401 { throw MusicSourceError.notAuthorized }
        guard 200..<300 ~= http.statusCode else { throw MusicSourceError.network("HTTP \(http.statusCode)") }

        struct TopArtists: Codable {
            struct Item: Codable { let name: String; let genres: [String] }
            let items: [Item]
        }
        let top = try JSONDecoder().decode(TopArtists.self, from: data)
        guard !top.items.isEmpty else { throw MusicSourceError.noData }

        // El ranking implica frecuencia: peso decreciente por posición.
        var genreCounts: [String: Double] = [:]
        let artists = top.items.enumerated().map { i, item in
            let weight = Double(top.items.count - i)
            for g in item.genres { genreCounts[g, default: 0] += weight }
            return ArtistPlay(name: item.name, plays: top.items.count - i, genres: item.genres)
        }
        let total = max(genreCounts.values.reduce(0, +), 1)
        let genres = genreCounts.sorted { $0.value > $1.value }.prefix(8)
            .map { GenreWeight(genre: $0.key, weight: $0.value / total) }

        return MusicSnapshot(artists: artists, genres: Array(genres), capturedAt: Date(), source: .spotify)
    }

    // MARK: - PKCE helpers

    private static func randomVerifier() -> String {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        return String((0..<64).map { _ in chars.randomElement()! })
    }

    private static func codeChallenge(_ verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Ancla de presentación para ASWebAuthenticationSession.
private final class PresentationAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = PresentationAnchor()
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        ASPresentationAnchor()
    }
}
