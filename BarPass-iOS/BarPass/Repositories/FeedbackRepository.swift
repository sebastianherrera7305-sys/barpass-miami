import Foundation

/// "¿Qué podemos hacer mejor?" — the one thing worth asking at the moment
/// somebody is about to delete the app.
///
/// Insert-only: `app_feedback` has no select policy and the table's SELECT is
/// revoked (supabase/app_feedback.sql), so this can write a message and can
/// never read anyone's back — including its own author's.
protocol FeedbackRepository: Sendable {
    func send(_ message: String) async throws
}

final actor SupabaseFeedbackRepository: FeedbackRepository {
    func send(_ message: String) async throws {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Signed in when possible so we can answer, anonymous otherwise —
        // a guest's reason for leaving is worth just as much, and demanding
        // an account here would lose exactly the feedback we're after.
        let session = try? await SupabaseRESTClient.freshSession()
        var row: [String: String] = [
            "message": String(trimmed.prefix(2000)),
            "app_version": Self.appVersion,
        ]
        if let userId = session?.user.id { row["user_id"] = userId }

        let request = try SupabaseRESTClient.request(
            "POST", path: "app_feedback",
            body: try SupabaseRESTClient.encoder.encode(row),
            accessToken: session?.accessToken,
            // `return=minimal`: there is no read permission on this table, so
            // asking for the inserted row back would fail the whole insert.
            extraHeaders: ["Prefer": "return=minimal"]
        )
        _ = try await SupabaseRESTClient.send(request)
    }

    private static var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
