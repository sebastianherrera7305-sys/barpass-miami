import Foundation

@MainActor
final class TripStore: ObservableObject {
    @Published var trips: [Trip] = []
    @Published var ratings: [TripRating] = []
    @Published var isLoading = false
    @Published var loadError: String?

    private let repository: TripRepository

    /// Blind ratings persist to disk — they were memory-only and vanished
    /// on every app restart (defeating the whole reputation system).
    private static let ratingsURL: URL = {
        let base = (FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("BarPassTrips", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("ratings.json")
    }()

    init(repository: TripRepository) {
        self.repository = repository
        ratings = (try? Data(contentsOf: Self.ratingsURL))
            .flatMap { try? JSONDecoder().decode([TripRating].self, from: $0) } ?? []
    }

    private func persistRatings() {
        if let data = try? JSONEncoder().encode(ratings) {
            try? data.write(to: Self.ratingsURL, options: .atomic)
        }
    }

    static var currentUserId: String {
        AuthService.shared.restoreSession()?.user.id ?? "me"
    }

    var myTrips: [Trip] {
        let uid = Self.currentUserId
        return trips
            .filter { $0.creatorId == uid || $0.memberIds.contains(uid) }
            .sorted { $0.startDate < $1.startDate }
    }

    /// Public/semi-open trips from other users that this account hasn't
    /// joined yet — only visible at all because the backend's RLS already
    /// scopes `getTrips()` to "mine + joinable", so no extra fetch needed.
    var discoverableTrips: [Trip] {
        let uid = Self.currentUserId
        return trips
            .filter { $0.visibility != .privateTrip && $0.creatorId != uid && !$0.memberIds.contains(uid) }
            .sorted { $0.startDate < $1.startDate }
    }

    func loadTrips() async {
        isLoading = true
        let repo = repository
        do {
            trips = try await repo.getTrips()
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    func create(_ trip: Trip) async {
        var t = trip
        t.creatorId = Self.currentUserId
        if !t.memberIds.contains(t.creatorId) { t.memberIds.insert(t.creatorId, at: 0) }
        let repo = repository
        do {
            try await repo.saveTrip(t)
            trips.insert(t, at: 0)
        } catch {
            loadError = error.localizedDescription
        }
    }

    func addStop(_ stop: Stop, to tripId: String) {
        guard let i = trips.firstIndex(where: { $0.id == tripId }) else { return }
        trips[i].stops.append(stop)
        let repo = repository
        let trip = trips[i]
        Task { try? await repo.updateTrip(trip) }
    }

    func delete(_ trip: Trip) async {
        let repo = repository
        do {
            try await repo.deleteTrip(trip)
            trips.removeAll { $0.id == trip.id }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func mutate(_ tripId: String, _ block: (inout Trip) -> Void) {
        guard let i = trips.firstIndex(where: { $0.id == tripId }) else { return }
        var t = trips[i]; block(&t); trips[i] = t
        let repo = repository
        let trip = t
        Task { try? await repo.updateTrip(trip) }
    }

    func joinStop(_ stopId: String, in tripId: String, user: String = currentUserId) {
        mutate(tripId) { t in
            guard let s = t.stops.firstIndex(where: { $0.id == stopId }) else { return }
            if !t.stops[s].joinedUserIds.contains(user) { t.stops[s].joinedUserIds.append(user) }
            t.stops[s].pendingStopRequests.removeAll { $0 == user }
        }
    }

    func requestJoinStop(_ stopId: String, in tripId: String, user: String) {
        mutate(tripId) { t in
            guard let s = t.stops.firstIndex(where: { $0.id == stopId }) else { return }
            if !t.stops[s].pendingStopRequests.contains(user) { t.stops[s].pendingStopRequests.append(user) }
        }
    }

    func rejectStopRequest(_ stopId: String, in tripId: String, user: String) {
        mutate(tripId) { t in
            guard let s = t.stops.firstIndex(where: { $0.id == stopId }) else { return }
            t.stops[s].pendingStopRequests.removeAll { $0 == user }
        }
    }

    func promoteToMember(_ user: String, in tripId: String) {
        mutate(tripId) { t in if !t.memberIds.contains(user) { t.memberIds.append(user) } }
    }

    func completeTrip(_ tripId: String) {
        mutate(tripId) { $0.status = .completed }
    }

    /// Basic edit — title/city/dates/visibility/cover. Doesn't touch stops;
    /// itinerary editing is a separate, larger feature not built yet.
    func updateBasicInfo(
        _ tripId: String,
        title: String,
        destinationCity: String,
        startDate: Date,
        endDate: Date,
        visibility: TripVisibility,
        coverImage: String?
    ) {
        mutate(tripId) { t in
            t.title = title
            t.destinationCity = destinationCity
            t.startDate = startDate
            t.endDate = endDate
            t.visibility = visibility
            if let coverImage { t.coverImage = coverImage }
        }
    }

    // MARK: - Group management

    /// Grants or revokes co-organizer status. Only meaningful for existing
    /// members — the creator's organizer role can't be changed this way,
    /// use `transferOwnership` for that.
    func setCoOrganizer(_ userId: String, in tripId: String, isCoOrganizer: Bool) {
        mutate(tripId) { t in
            guard userId != t.creatorId, t.memberIds.contains(userId) else { return }
            var ids = t.coOrganizerIds ?? []
            if isCoOrganizer {
                if !ids.contains(userId) { ids.append(userId) }
            } else {
                ids.removeAll { $0 == userId }
            }
            t.coOrganizerIds = ids
        }
    }

    /// Removes a member entirely: from the trip, from co-organizers, and
    /// from every stop's joined/pending lists. Can't remove the creator —
    /// use `transferOwnership` first if the creator wants to leave.
    func removeMember(_ userId: String, from tripId: String) {
        mutate(tripId) { t in
            guard userId != t.creatorId else { return }
            t.memberIds.removeAll { $0 == userId }
            t.coOrganizerIds?.removeAll { $0 == userId }
            t.pendingRequests.removeAll { $0 == userId }
            for i in t.stops.indices {
                t.stops[i].joinedUserIds.removeAll { $0 == userId }
                t.stops[i].pendingStopRequests.removeAll { $0 == userId }
            }
        }
    }

    /// A non-creator member leaving voluntarily — same cleanup as
    /// `removeMember`, exposed separately so the UI can label/gate it
    /// differently (no permission check needed, you can always remove
    /// yourself).
    func leaveTrip(_ tripId: String, userId: String = currentUserId) {
        removeMember(userId, from: tripId)
    }

    /// Transfers the organizer role to another current member. The old
    /// creator is kept on as a co-organizer rather than dropped to a plain
    /// member, so they don't lose all control by handing off ownership.
    func transferOwnership(to newOwnerId: String, in tripId: String) {
        mutate(tripId) { t in
            guard t.memberIds.contains(newOwnerId), newOwnerId != t.creatorId else { return }
            let oldOwner = t.creatorId
            t.creatorId = newOwnerId
            var coOrgs = t.coOrganizerIds ?? []
            coOrgs.removeAll { $0 == newOwnerId }
            if !coOrgs.contains(oldOwner) { coOrgs.append(oldOwner) }
            t.coOrganizerIds = coOrgs
        }
    }

    /// Generates (or returns the existing) invite code for a trip. Codes are
    /// short and human-shareable — meant to be copied/shared via the
    /// system share sheet, not a full custom invite-channel integration.
    @discardableResult
    func ensureInviteCode(for tripId: String) -> String {
        if let existing = trips.first(where: { $0.id == tripId })?.inviteCode, !existing.isEmpty {
            return existing
        }
        let code = Self.randomInviteCode()
        mutate(tripId) { $0.inviteCode = code }
        return code
    }

    private static func randomInviteCode(length: Int = 6) -> String {
        // Avoids visually-ambiguous characters (0/O, 1/I/L).
        let chars = Array("23456789ABCDEFGHJKMNPQRSTUVWXYZ")
        return String((0..<length).compactMap { _ in chars.randomElement() })
    }

    /// Joins a trip by its invite code — delegates to the repository, which
    /// does the lookup+join server-side (via a SECURITY DEFINER RPC on
    /// Supabase) rather than a plain client-side filter, so this can resolve
    /// even private trips the caller has never seen without leaking anyone
    /// else's private trips in the process.
    func joinByInviteCode(_ code: String) async throws {
        let trip = try await repository.joinByInviteCode(code)
        if let i = trips.firstIndex(where: { $0.id == trip.id }) {
            trips[i] = trip
        } else {
            trips.insert(trip, at: 0)
        }
    }

    func submitRating(scopeId: String, rateeId: String, score: Int, tags: [String]) {
        let rater = Self.currentUserId
        guard !ratings.contains(where: { $0.scopeId == scopeId && $0.raterId == rater && $0.rateeId == rateeId }) else { return }
        ratings.append(TripRating(scopeId: scopeId, raterId: rater, rateeId: rateeId, score: score, tags: tags))
        let reciprocal = ratings.contains { $0.scopeId == scopeId && $0.raterId == rateeId && $0.rateeId == rater }
        if reciprocal {
            for idx in ratings.indices where ratings[idx].scopeId == scopeId
                && ((ratings[idx].raterId == rater && ratings[idx].rateeId == rateeId)
                    || (ratings[idx].raterId == rateeId && ratings[idx].rateeId == rater)) {
                ratings[idx].visible = true
            }
        }
        persistRatings()
    }

    func reputation(for userId: String) -> UserReputation {
        let completed = trips.filter { $0.status == .completed && $0.memberIds.contains(userId) }.count
        let visibleScores = ratings.filter { $0.rateeId == userId && $0.visible }.map { Double($0.score) }
        let avg = visibleScores.isEmpty ? 0 : visibleScores.reduce(0, +) / Double(visibleScores.count)
        let badge: ReputationBadge = completed >= 10 ? .verified : (completed >= 3 ? .trustedPlanner : .new)
        return UserReputation(userId: userId, badge: badge, completedTripsCount: completed, avgScore: avg)
    }
}
