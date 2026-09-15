import Foundation

/// Where a person sits in the caller's own graph. The server is the only
/// authority on this — every RPC recomputes it — so the client never
/// infers "we're friends" from a cached list.
enum FriendRelation: String, Codable, Sendable {
    /// Mutually accepted. This is the only state that unlocks DMs and
    /// presence.
    case friend
    /// They asked me; I have not answered.
    case incoming
    /// I asked them; they have not answered.
    case outgoing
    /// No edge at all.
    case none

    init(rawValueOrNone raw: String?) {
        self = raw.flatMap(FriendRelation.init(rawValue:)) ?? .none
    }
}

/// A row from `list_friends()` — one entry per edge touching me, whether
/// accepted or still pending in either direction.
struct FriendEdge: Codable, Identifiable, Sendable, Hashable {
    let userId: String
    let displayName: String?
    let avatarUrl: String?
    /// 'friend' | 'incoming' | 'outgoing'
    let direction: String
    let since: Date

    var id: String { userId }
    var relation: FriendRelation { FriendRelation(rawValueOrNone: direction) }
    /// Someone who never set a display name still has to be addressable.
    var name: String { displayName?.isEmpty == false ? displayName! : L10n.tSync("friends.unnamed") }
}

/// A row from `search_profiles()` / `redeem_friend_code()`. Deliberately
/// carries nothing but a name, an avatar and the relationship — no email,
/// no phone, no location. Search results are the easiest place to leak a
/// directory, so the payload is kept to exactly what the row has to render.
struct FriendSearchResult: Codable, Identifiable, Sendable, Hashable {
    let userId: String
    let displayName: String?
    let avatarUrl: String?
    /// 'friend' | 'incoming' | 'outgoing' | 'none'
    let relation: String

    var id: String { userId }
    var relationState: FriendRelation { FriendRelation(rawValueOrNone: relation) }
    var name: String { displayName?.isEmpty == false ? displayName! : L10n.tSync("friends.unnamed") }
}

/// A friend who is checked into a venue inside the night still in
/// progress, from `get_friends_out_tonight()`.
///
/// This is venue-granularity, not GPS: the coordinates here are the
/// VENUE's, taken from the catalogue, never the friend's device. The
/// friend published this by tapping "I'm here"; the app is not tracking
/// them.
struct FriendPresence: Codable, Identifiable, Sendable, Hashable {
    let userId: String
    let displayName: String?
    let avatarUrl: String?
    let venueId: String
    let venueName: String
    let venueLat: Double
    let venueLng: Double
    let checkedInAt: Date

    var id: String { userId }
    var name: String { displayName?.isEmpty == false ? displayName! : L10n.tSync("friends.unnamed") }
}

/// One decrypted DM. `text` arrives as plaintext only because
/// `get_friend_messages()` decrypted it server-side; the row on disk is
/// ciphertext (see friend_graph_schema.sql section 8).
struct FriendMessage: Codable, Identifiable, Sendable, Hashable {
    let id: String
    let threadId: String
    let senderId: String
    let text: String
    let createdAt: Date
}

/// An inbox row from `list_friend_threads()`.
struct FriendThreadSummary: Codable, Identifiable, Sendable, Hashable {
    let userId: String
    let displayName: String?
    let avatarUrl: String?
    let lastMessageAt: Date?
    let hasUnread: Bool

    var id: String { userId }
    var name: String { displayName?.isEmpty == false ? displayName! : L10n.tSync("friends.unnamed") }
}

/// Errors the friend RPCs raise by name. Mapping them here keeps the
/// Postgres error strings out of the UI — a user should never see
/// `not_friends` or a raw PostgREST envelope.
///
/// Note that `userNotFound` is deliberately what a BLOCKED target also
/// returns: the server refuses to distinguish "no such person" from "that
/// person blocked you", so a blocked user cannot probe their way to
/// confirming it. The client must not try to be cleverer than that.
enum FriendError: LocalizedError, Sendable {
    case notAuthenticated
    case userNotFound
    case codeNotFound
    case codeIsYourOwn
    case notFriends
    case rateLimited
    case noPendingRequest
    case unknown

    static func from(responseBody: String) -> FriendError {
        if responseBody.contains("not_authenticated") { return .notAuthenticated }
        if responseBody.contains("user_not_found") { return .userNotFound }
        if responseBody.contains("code_is_your_own") { return .codeIsYourOwn }
        if responseBody.contains("code_not_found") { return .codeNotFound }
        if responseBody.contains("not_friends") { return .notFriends }
        if responseBody.contains("rate_limit_exceeded") { return .rateLimited }
        if responseBody.contains("no_pending_request") { return .noPendingRequest }
        return .unknown
    }

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return L10n.tSync("friends.error.signIn")
        case .userNotFound: return L10n.tSync("friends.error.userNotFound")
        case .codeNotFound: return L10n.tSync("friends.error.codeNotFound")
        case .codeIsYourOwn: return L10n.tSync("friends.error.ownCode")
        case .notFriends: return L10n.tSync("friends.error.notFriends")
        case .rateLimited: return L10n.tSync("friends.error.rateLimited")
        case .noPendingRequest: return L10n.tSync("friends.error.noRequest")
        case .unknown: return L10n.tSync("friends.error.generic")
        }
    }
}
