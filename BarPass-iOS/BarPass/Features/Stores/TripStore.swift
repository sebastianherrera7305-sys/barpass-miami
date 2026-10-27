import Foundation

@MainActor
final class TripStore: ObservableObject {
    @Published var trips: [Trip] = []
    /// Session-only cache of reputations fetched from the server. NOT
    /// persisted — a persisted cache would re-introduce the exact bug
    /// this entire rewrite exists to fix (local data posing as the
    /// authoritative trust signal). Absent entries render as `.new`;
    /// callers call `refreshReputation(for:)` from a `.task` to fill in.
    @Published private(set) var reputations: [String: UserReputation] = [:]
    @Published var isLoading = false
    @Published var loadError: String?

    private let repository: TripRepository

    init(repository: TripRepository) {
        self.repository = repository
        // One-shot cleanup of the pre-migration local ratings file.
        // Was per-device JSON — the agent-trust badges it fed were
        // actively misleading because they only reflected ratings held
        // on the viewer's own device. Keeping this deletion forever
        // means a resurrected old build can't re-populate the file.
        let legacy = (FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("BarPassTrips", isDirectory: true)
            .appendingPathComponent("ratings.json")
        try? FileManager.default.removeItem(at: legacy)
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
        loadError = nil
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
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    func addStop(_ stop: Stop, to tripId: String) {
        guard let i = trips.firstIndex(where: { $0.id == tripId }) else { return }
        let original = trips[i]
        trips[i].stops.append(stop)
        let repo = repository
        let trip = trips[i]
        // Optimistic update, rolled back on failure — this used to fire
        // `try? await repo.updateTrip(trip)` and swallow the error, so a
        // rejected/offline PATCH left the UI showing a stop that was never
        // actually saved, silently reverting on the next loadTrips() with
        // no explanation.
        Task {
            do {
                try await repo.updateTrip(trip)
            } catch {
                await MainActor.run {
                    if let idx = self.trips.firstIndex(where: { $0.id == tripId }) {
                        self.trips[idx] = original
                    }
                    self.loadError = error.localizedDescription
                }
            }
        }
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
        let original = trips[i]
        var t = original; block(&t); trips[i] = t
        let repo = repository
        let trip = t
        // Same optimistic-update-with-rollback as addStop() above — this
        // backs every mutate()-based method below (join/leave a stop,
        // promote a member, transfer ownership, complete a trip, edit basic
        // info) so a rejected/offline PATCH is visibly undone instead of
        // silently reverting on the next fetch.
        Task {
            do {
                try await repo.updateTrip(trip)
            } catch {
                await MainActor.run {
                    if let idx = self.trips.firstIndex(where: { $0.id == tripId }) {
                        self.trips[idx] = original
                    }
                    self.loadError = error.localizedDescription
                }
            }
        }
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

    /// Server-authoritative completion. Returns the updated trip from
    /// the RPC (which also takes the member snapshot) so the local list
    /// stays in sync without a second round trip. Throws so callers can
    /// surface the specific error (not_organizer, need_two_members,
    /// etc.) instead of silently reverting.
    func completeTrip(_ tripId: String) async throws {
        let updated = try await repository.completeTrip(tripId)
        if let i = trips.firstIndex(where: { $0.id == tripId }) {
            trips[i] = updated
        }
    }

    /// Submit a rating via the server RPC. Caller handles the error.
    func submitRating(
        tripId: String, scopeKind: String, scopeId: String,
        rateeId: String, score: Int, tags: [String]
    ) async throws {
        try await repository.submitRating(
            tripId: tripId, scopeKind: scopeKind, scopeId: scopeId,
            rateeId: rateeId, score: score, tags: tags
        )
        // Invalidate any cached reputation for the ratee — if the
        // counter-rating already exists, the ratings_count/avg_score they
        // see should update right away.
        reputations.removeValue(forKey: rateeId)
    }

    /// Fire-and-forget cache fill. UI calls this from `.task` on row
    /// appear. Errors are swallowed intentionally — a missing reputation
    /// renders as `.new`, same as a brand-new user, which is the correct
    /// fallback. (The server's own `not_visible` error for strangers also
    /// lands here as a null cache entry — rendering .new is the right
    /// outcome in that case too, since the organizer shouldn't be told
    /// "this person has a reputation you can't see" either.)
    func refreshReputation(for userId: String) async {
        if reputations[userId] != nil { return }   // simple de-dup
        do {
            let rep = try await repository.getUserReputation(userId)
            reputations[userId] = rep
        } catch {
            // Leave absent. UI defaults to .new.
        }
    }

    /// User-driven stop reorder. Owner report (TestFlight 2026-10-27,
    /// "cada parada del trip debería o el usuario poder organizarlo en
    /// el orden que ellos quieren ir"): until now the itinerary was auto-
    /// sorted by resolved start time, so a user could not move stop #3
    /// to the top. This reassigns the existing time slots in itinerary
    /// order to the new stop sequence — the slots themselves stay the
    /// same (22:00 / 23:30 / 01:00 are preserved), only *which* stop
    /// occupies each slot changes. Stops without a startTime keep theirs
    /// as-is; their order within untimed-stops is still honored by the
    /// sorter's stable tiebreak on array position.
    ///
    /// `newStopIdOrder` is the full list of stop ids in the order the
    /// user wants them to appear. Unknown ids are ignored, missing ones
    /// are appended at the end to keep the trip from losing stops.
    func reorderStops(_ tripId: String, newStopIdOrder: [String]) {
        mutate(tripId) { t in
            var byId: [String: Stop] = Dictionary(uniqueKeysWithValues: t.stops.map { ($0.id, $0) })
            var reordered: [Stop] = []
            for id in newStopIdOrder {
                if let s = byId.removeValue(forKey: id) {
                    reordered.append(s)
                }
            }
            // Append any stops the caller forgot — never lose data.
            reordered.append(contentsOf: byId.values)
            // Re-assign existing time slots in itinerary order so the
            // sorter (sortedStops) ends up matching the user's intent.
            // Collect the ORIGINAL non-empty startTimes in itinerary
            // order and hand them out to the new array in the same
            // positions. Stops that had no startTime keep "".
            let originalStartTimes = t.stops.map { $0.startTime }.filter { !$0.isEmpty }
            var slotIdx = 0
            for i in reordered.indices {
                if slotIdx < originalStartTimes.count {
                    reordered[i].startTime = originalStartTimes[slotIdx]
                    slotIdx += 1
                } else {
                    reordered[i].startTime = ""
                }
            }
            t.stops = reordered
        }
    }

    /// Remove a stop from the trip (owner report 2026-10-27, "También tiene
    /// que tener para eliminar de el orden"). Any user who was joined/pending
    /// on that stop quietly loses that reference — the stop itself is gone.
    func removeStop(_ stopId: String, from tripId: String) {
        mutate(tripId) { t in
            t.stops.removeAll { $0.id == stopId }
        }
    }

    /// Change a single stop's start time (owner report 2026-10-27, "para
    /// cambiar los Horarios"). Caller passes "h:mm a" (e.g. "10:30 PM") or ""
    /// to clear it. Nothing else about the stop changes — the venue stays,
    /// the joined members stay. The itinerary sorter re-reads startTime on
    /// the next render so a time edit also reshuffles the order visually.
    func updateStopStartTime(_ stopId: String, in tripId: String, startTime: String) {
        mutate(tripId) { t in
            guard let s = t.stops.firstIndex(where: { $0.id == stopId }) else { return }
            t.stops[s].startTime = startTime
        }
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

    /// Synchronous read of the cached reputation. Returns `.new` if the
    /// server hasn't been asked yet — UI should pair this with
    /// `.task { await refreshReputation(for: userId) }` on row appear.
    /// Not a fallback to local computation anymore: the server is the
    /// only source of truth.
    func reputation(for userId: String) -> UserReputation {
        reputations[userId]
            ?? UserReputation(userId: userId, badge: .new, completedTripsCount: 0, avgScore: 0)
    }
}
