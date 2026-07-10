import Foundation

/// Single point of dependency injection for the repository layer.
/// Swap implementations here — views and stores never change.
enum RepositoryDependencies {
    nonisolated(unsafe) static var venue: VenueRepository = SupabaseVenueRepository()
    // Disk-backed until Supabase Auth + trips/night_plans schemas land
    // (the Supabase implementations are registered and ready to swap in).
    nonisolated(unsafe) static var trip: TripRepository = LocalTripRepository()
    nonisolated(unsafe) static var plan: PlanRepository = LocalPlanRepository()
    nonisolated(unsafe) static var post: PostRepository = SupabasePostRepository()
}
