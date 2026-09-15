import Foundation

/// The friend graph: request / accept / remove / block, discovery, and
/// "who's out tonight".
///
/// Every method here is a call to a SECURITY DEFINER RPC, never a table
/// read. That is not ceremony — `friendships` is readable by its two
/// members only and `profiles` is readable by its owner only, so there is
/// literally no PostgREST query that can return a friend's display name.
/// The RPCs are the only door, and they re-check blocks and mutual
/// acceptance on every single call.
protocol FriendsRepository: Sendable {
    func list() async throws -> [FriendEdge]
    func search(query: String) async throws -> [FriendSearchResult]
    func request(userId: String) async throws
    func accept(userId: String) async throws
    /// Decline, cancel, or unfriend — one server-side path for all three.
    func remove(userId: String) async throws
    func block(userId: String) async throws
    func unblock(userId: String) async throws
    func myFriendCode() async throws -> String
    func redeem(code: String) async throws -> FriendSearchResult
    func friendsOutTonight() async throws -> [FriendPresence]
    func setLocationSharing(_ enabled: Bool) async throws
    func locationSharingEnabled() async throws -> Bool
}

final actor SupabaseFriendsRepository: FriendsRepository {

    // MARK: - Graph

    func list() async throws -> [FriendEdge] {
        try await decodeRPC("list_friends", body: "{}")
    }

    func request(userId: String) async throws {
        _ = try await callRPC("request_friend", body: ["p_user_id": userId])
    }

    func accept(userId: String) async throws {
        _ = try await callRPC("accept_friend", body: ["p_user_id": userId])
    }

    func remove(userId: String) async throws {
        _ = try await callRPC("remove_friend", body: ["p_user_id": userId])
    }

    func block(userId: String) async throws {
        _ = try await callRPC("block_user", body: ["p_user_id": userId])
    }

    func unblock(userId: String) async throws {
        _ = try await callRPC("unblock_user", body: ["p_user_id": userId])
    }

    // MARK: - Discovery

    /// The server enforces a 2-character minimum; short-circuiting here
    /// too just avoids a round trip per keystroke while someone types.
    func search(query: String) async throws -> [FriendSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        return try await decodeRPC("search_profiles", body: ["p_query": trimmed])
    }

    /// Idempotent server-side: the same code comes back every time.
    func myFriendCode() async throws -> String {
        let data = try await callRPC("get_or_create_friend_code", body: [:])
        // A bare scalar RPC returns a JSON string, quotes included.
        if let code = try? SupabaseRESTClient.decoder.decode(String.self, from: data) { return code }
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"\n ")) ?? ""
    }

    func redeem(code: String) async throws -> FriendSearchResult {
        let rows: [FriendSearchResult] = try await decodeRPC("redeem_friend_code", body: ["p_code": code])
        guard let first = rows.first else { throw FriendError.codeNotFound }
        return first
    }

    // MARK: - Presence

    /// Returns an empty list — not an error — when the caller has location
    /// sharing off, because the server makes sharing reciprocal. The UI
    /// has to say why rather than showing a bare "no friends out".
    func friendsOutTonight() async throws -> [FriendPresence] {
        try await decodeRPC("get_friends_out_tonight", body: "{}")
    }

    func setLocationSharing(_ enabled: Bool) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["p_enabled": enabled])
        _ = try await callRPC("set_location_sharing", rawBody: body)
    }

    /// Read straight off the caller's own profile row — `profiles` RLS is
    /// "read own profile", so this can only ever return the signed-in
    /// user's own setting, never anyone else's.
    func locationSharingEnabled() async throws -> Bool {
        let session = try await SupabaseRESTClient.freshSession()
        let request = try SupabaseRESTClient.request(
            "GET", path: "profiles",
            queryItems: [
                URLQueryItem(name: "id", value: "eq.\(session.user.id)"),
                URLQueryItem(name: "select", value: "share_location_with_friends"),
            ],
            accessToken: session.accessToken
        )
        let data = try await SupabaseRESTClient.send(request)
        struct Row: Decodable { let shareLocationWithFriends: Bool? }
        return try SupabaseRESTClient.decoder.decode([Row].self, from: data).first?.shareLocationWithFriends ?? false
    }

    // MARK: - Transport

    private func decodeRPC<T: Decodable>(_ name: String, body: [String: String]) async throws -> [T] {
        let data = try await callRPC(name, body: body)
        return try SupabaseRESTClient.decoder.decode([T].self, from: data)
    }

    private func decodeRPC<T: Decodable>(_ name: String, body: String) async throws -> [T] {
        let data = try await callRPC(name, rawBody: Data(body.utf8))
        return try SupabaseRESTClient.decoder.decode([T].self, from: data)
    }

    private func callRPC(_ name: String, body: [String: String]) async throws -> Data {
        try await callRPC(name, rawBody: try JSONSerialization.data(withJSONObject: body))
    }

    /// Reads the failure body instead of letting `SupabaseRESTClient.send`
    /// collapse everything into `badServerResponse` — the RPCs raise named
    /// errors (`user_not_found`, `rate_limit_exceeded`, …) and losing them
    /// would mean every friend-graph failure surfaced as the same useless
    /// "something went wrong". Same deliberate exception
    /// `VenueCheckinRepository` makes.
    private func callRPC(_ name: String, rawBody: Data) async throws -> Data {
        let session = try await SupabaseRESTClient.freshSession()
        let request = try SupabaseRESTClient.request(
            "POST", path: "rpc/\(name)", body: rawBody, accessToken: session.accessToken
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FriendError.unknown }
        guard 200..<300 ~= http.statusCode else {
            throw FriendError.from(responseBody: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }
}
