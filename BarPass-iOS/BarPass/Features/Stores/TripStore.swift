import Foundation

@MainActor
final class TripStore: ObservableObject {
    @Published var trips: [Trip] = []
    @Published var ratings: [TripRating] = []
    @Published var isLoading = false
    @Published var loadError: String?

    private let repository: TripRepository

    init(repository: TripRepository) {
        self.repository = repository
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
    }

    func reputation(for userId: String) -> UserReputation {
        let completed = trips.filter { $0.status == .completed && $0.memberIds.contains(userId) }.count
        let visibleScores = ratings.filter { $0.rateeId == userId && $0.visible }.map { Double($0.score) }
        let avg = visibleScores.isEmpty ? 0 : visibleScores.reduce(0, +) / Double(visibleScores.count)
        let badge: ReputationBadge = completed >= 10 ? .verified : (completed >= 3 ? .trustedPlanner : .new)
        return UserReputation(userId: userId, badge: badge, completedTripsCount: completed, avgScore: avg)
    }
}
