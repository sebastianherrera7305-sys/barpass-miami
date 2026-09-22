import Foundation

/// Calls barpass-v2's `/api/safety/notify`, which fans a safety-group event
/// out over APNs. The client names a seek or a group it belongs to; it never
/// sends a token or a recipient list — the server derives recipients in SQL
/// (`get_seek_push_targets`: the LEADER of that seek and nobody else) and
/// re-checks membership and blocks there.
///
/// Every function here is best-effort and never throws: by the time it runs
/// the seek / message is already saved server-side, so a push that fails is a
/// weaker delivery, not a lost search.
enum SafetyPushClient {

    private static let timeout: TimeInterval = 10

    /// STATE B: tells the leader — only the leader — that someone is looking
    /// for them and to open BarPass to connect the radar.
    static func notifySeekLeader(seekId: String) async -> PushDelivery {
        await post(["type": "seek_leader", "seekId": seekId])
    }

    /// Silent "refresh the group" (new message, someone joined, the event
    /// ended). Result ignored by callers on purpose.
    static func notifyRefresh(groupId: String) async {
        _ = await post(["type": "refresh", "groupId": groupId])
    }

    /// Pure, so the mapping from the route's answers to what the UI says is
    /// testable (BarPassTests/SafetyGroupTests.swift).
    static func delivery(status: Int, body: [String: Any]) -> PushDelivery {
        if status == 503 { return .unavailable }
        guard (200..<300).contains(status) else { return .failed }
        let recipients = body["recipients"] as? Int ?? 0
        let sent = body["sent"] as? Int ?? 0
        if recipients == 0 { return .unavailable }
        // `sent` cuenta respuestas 200 de APNs = ACEPTADO PARA ENTREGA, no
        // entregado ni visto (ver `PushDelivery`).
        return sent > 0 ? .accepted(recipients: sent) : .failed
    }

    private static func post(_ payload: [String: Any]) async -> PushDelivery {
        guard let session = try? await SupabaseRESTClient.freshSession() else { return .failed }
        var request = URLRequest(url: APIClient.baseURL.appendingPathComponent("safety/notify"))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return .failed }
        request.httpBody = body

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return .failed }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return delivery(status: http.statusCode, body: json)
    }
}
