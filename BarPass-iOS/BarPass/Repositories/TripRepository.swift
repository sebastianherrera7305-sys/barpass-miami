import Foundation

protocol TripRepository: Sendable {
    func getTrips() async throws -> [Trip]
    func saveTrip(_ trip: Trip) async throws
    func updateTrip(_ trip: Trip) async throws
    func deleteTrip(_ trip: Trip) async throws
}
