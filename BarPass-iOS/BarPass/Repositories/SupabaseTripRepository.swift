import Foundation

/// Placeholder until Supabase Auth + the `trips`/`stops` schema with RLS are
/// live (tables verified ABSENT on 2026-07-09 — every call 404'd, which is
/// why `RepositoryDependencies.trip` defaults to `LocalTripRepository`).
/// Throws loudly instead of failing silently.
actor SupabaseTripRepository: TripRepository {
    struct NotWiredError: LocalizedError {
        var errorDescription: String? { "SupabaseTripRepository: tablas trips/stops aún no existen en Supabase." }
    }

    func getTrips() async throws -> [Trip] { throw NotWiredError() }
    func saveTrip(_ trip: Trip) async throws { throw NotWiredError() }
    func updateTrip(_ trip: Trip) async throws { throw NotWiredError() }
    func deleteTrip(_ trip: Trip) async throws { throw NotWiredError() }
}
