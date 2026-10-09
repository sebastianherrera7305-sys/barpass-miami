import Foundation

protocol TripRepository: Sendable {
    func getTrips() async throws -> [Trip]
    func saveTrip(_ trip: Trip) async throws
    func updateTrip(_ trip: Trip) async throws
    func deleteTrip(_ trip: Trip) async throws
    /// Looks up a trip by its invite code and joins the current user to it,
    /// returning the (now-updated) trip. Implementations must not leak other
    /// users' private trips while doing the lookup.
    func joinByInviteCode(_ code: String) async throws -> Trip

    /// Flips `trips.status` to `.completed` server-side AND takes a
    /// snapshot of who's a member right now — that snapshot is what the
    /// rating RPC validates against. Only the organizer or a
    /// co-organizer may call this; idempotent on re-call. The old whole-
    /// row PATCH path through `updateTrip` cannot do this anymore once
    /// the trips.status column grant is revoked, which is deliberate.
    func completeTrip(_ tripId: String) async throws -> Trip

    /// Submit a mutual peer rating. The server forces `rater_id =
    /// auth.uid()`; the client-supplied `rateeId` must be in the
    /// completion snapshot. Errors propagate as `TripRatingError` so
    /// the UI can distinguish `.alreadyRated` from `.rateLimited` etc.
    func submitRating(
        tripId: String, scopeKind: String, scopeId: String,
        rateeId: String, score: Int, tags: [String]
    ) async throws

    /// Reads a user's reputation from the server. Only visible to self,
    /// trip co-members, and friends (accepted or pending). Strangers
    /// get a thrown `TripRatingError.notVisible`.
    func getUserReputation(_ userId: String) async throws -> UserReputation
}

enum TripRatingError: LocalizedError, Sendable {
    case notAuthenticated
    case cannotRateSelf
    case invalidScore
    case tooManyTags
    case invalidScopeKind
    case tripNotCompleted
    case ratingWindowClosed
    case notAMember
    case rateeNotAMember
    case rateLimited
    case alreadyRated
    case notOrganizer
    case needTwoMembers
    case notVisible
    case unknown(String?)

    static func from(responseBody: String) -> TripRatingError {
        if responseBody.contains("not_authenticated") { return .notAuthenticated }
        if responseBody.contains("cannot_rate_self") { return .cannotRateSelf }
        if responseBody.contains("invalid_score") { return .invalidScore }
        if responseBody.contains("too_many_tags") { return .tooManyTags }
        if responseBody.contains("invalid_scope_kind") || responseBody.contains("scope_id_mismatch") { return .invalidScopeKind }
        if responseBody.contains("trip_not_completed") { return .tripNotCompleted }
        if responseBody.contains("rating_window_closed") { return .ratingWindowClosed }
        if responseBody.contains("ratee_not_a_member") { return .rateeNotAMember }
        if responseBody.contains("not_a_member") { return .notAMember }
        if responseBody.contains("rate_limited") { return .rateLimited }
        if responseBody.contains("already_rated") { return .alreadyRated }
        if responseBody.contains("not_organizer") { return .notOrganizer }
        if responseBody.contains("need_two_members") { return .needTwoMembers }
        if responseBody.contains("not_visible") { return .notVisible }
        return .unknown(responseBody.isEmpty ? nil : responseBody)
    }

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:  return L10n.tSync("friends.error.signIn")
        case .cannotRateSelf:    return L10n.tSync("trips.rating.error.self")
        case .invalidScore:      return L10n.tSync("trips.rating.error.score")
        case .tooManyTags:       return L10n.tSync("trips.rating.error.tags")
        case .invalidScopeKind:  return L10n.tSync("trips.rating.error.scope")
        case .tripNotCompleted:  return L10n.tSync("trips.rating.error.notCompleted")
        case .ratingWindowClosed:return L10n.tSync("trips.rating.error.windowClosed")
        case .notAMember:        return L10n.tSync("trips.rating.error.notMember")
        case .rateeNotAMember:   return L10n.tSync("trips.rating.error.rateeNotMember")
        case .rateLimited:       return L10n.tSync("trips.rating.error.rateLimited")
        case .alreadyRated:      return L10n.tSync("trips.rating.error.alreadyRated")
        case .notOrganizer:      return L10n.tSync("trips.rating.error.notOrganizer")
        case .needTwoMembers:    return L10n.tSync("trips.rating.error.needTwoMembers")
        case .notVisible:        return L10n.tSync("trips.rating.error.notVisible")
        case .unknown(let m):    return m ?? L10n.tSync("friends.error.generic")
        }
    }
}
