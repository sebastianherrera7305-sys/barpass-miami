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
}
