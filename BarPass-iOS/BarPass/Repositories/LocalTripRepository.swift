import Foundation

/// Disk-backed Trip store — the launch data source until Supabase Auth +
/// the trips schema are live. Trips survive app restarts (offline-first),
/// and the whole thing is swappable for `SupabaseTripRepository` with a
/// one-line change in `RepositoryDependencies`.
actor LocalTripRepository: TripRepository {
    private let fileURL: URL
    private var cache: [Trip]?

    init() {
        let baseDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let base = baseDir.appendingPathComponent("BarPassTrips", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("trips.json")
    }

    func getTrips() async throws -> [Trip] {
        if let cache { return cache }
        let trips = (try? Data(contentsOf: fileURL))
            .flatMap { try? JSONDecoder().decode([Trip].self, from: $0) } ?? []
        cache = trips
        return trips
    }

    func saveTrip(_ trip: Trip) async throws {
        var trips = try await getTrips()
        trips.removeAll { $0.id == trip.id }
        trips.insert(trip, at: 0)
        try write(trips)
    }

    func updateTrip(_ trip: Trip) async throws {
        var trips = try await getTrips()
        if let i = trips.firstIndex(where: { $0.id == trip.id }) { trips[i] = trip }
        else { trips.insert(trip, at: 0) }
        try write(trips)
    }

    func deleteTrip(_ trip: Trip) async throws {
        var trips = try await getTrips()
        trips.removeAll { $0.id == trip.id }
        try write(trips)
    }

    struct InviteNotFoundError: LocalizedError {
        var errorDescription: String? { "No encontramos ningún trip con ese código." }
    }

    /// Local-only, single-device best-effort: no RLS to worry about since
    /// this store only ever holds trips this device already had access to.
    func joinByInviteCode(_ code: String) async throws -> Trip {
        var trips = try await getTrips()
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let i = trips.firstIndex(where: { $0.inviteCode == normalized }) else {
            throw InviteNotFoundError()
        }
        let uid = AuthService.shared.restoreSession()?.user.id ?? "me"
        if !trips[i].memberIds.contains(uid) { trips[i].memberIds.append(uid) }
        try write(trips)
        return trips[i]
    }

    private func write(_ trips: [Trip]) throws {
        cache = trips
        try JSONEncoder().encode(trips).write(to: fileURL, options: .atomic)
    }
}
