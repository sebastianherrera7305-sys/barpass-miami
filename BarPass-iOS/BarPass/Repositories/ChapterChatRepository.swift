import Foundation

struct ChapterMessage: Codable, Identifiable, Sendable {
    let id: String
    let chapterId: String
    let userId: String?
    let text: String
    let createdAt: Date
    let isSystem: Bool
}

protocol ChapterChatRepository: Sendable {
    func messages(chapterId: String) async throws -> [ChapterMessage]
    func send(text: String) async throws
    func report(messageId: String, reason: String) async throws
}

final actor SupabaseChapterChatRepository: ChapterChatRepository {
    private static let supabaseURL = SupabaseConfig.url.absoluteString
    private static let anonKey = SupabaseConfig.anonKey

    private func freshSession() async throws -> AuthSession {
        guard await AuthService.shared.refreshIfNeeded(),
              let session = AuthService.shared.restoreSession() else {
            throw URLError(.userAuthenticationRequired)
        }
        return session
    }

    func messages(chapterId: String) async throws -> [ChapterMessage] {
        let session = try await freshSession()
        guard var components = URLComponents(string: "\(Self.supabaseURL)/rest/v1/chapter_messages") else { throw URLError(.badURL) }
        components.queryItems = [
            URLQueryItem(name: "select", value: "id,chapter_id,user_id,text,created_at,is_system"),
            URLQueryItem(name: "chapter_id", value: "eq.\(chapterId)"),
            URLQueryItem(name: "order", value: "created_at.asc"),
        ]
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.setValue(Self.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([ChapterMessage].self, from: data)
    }

    /// RPC enforces affiliation + ban + rate limit server-side — the client
    /// never decides which chapter it's posting to.
    func send(text: String) async throws {
        let session = try await freshSession()
        guard let url = URL(string: "\(Self.supabaseURL)/rest/v1/rpc/send_chapter_message") else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(Self.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["p_text": text])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            let message = String(data: data, encoding: .utf8) ?? "unknown"
            throw NSError(domain: "ChapterChat", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    func report(messageId: String, reason: String) async throws {
        let session = try await freshSession()
        guard let url = URL(string: "\(Self.supabaseURL)/rest/v1/rpc/report_chapter_message") else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(Self.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["p_message_id": messageId, "p_reason": reason])

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
    }
}
