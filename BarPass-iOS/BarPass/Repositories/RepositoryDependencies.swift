import Foundation

/// Single point of dependency injection for the repository layer.
/// Swap implementations here — views and stores never change.
enum RepositoryDependencies {
    nonisolated(unsafe) static var venue: VenueRepository = SupabaseVenueRepository()
    // Real shared backend — requires barpass-v2/supabase/trips_schema.sql to
    // have been run in the Supabase SQL editor. Needs a signed-in session;
    // guest mode can't read/write trips (RLS scopes everything to auth.uid()).
    nonisolated(unsafe) static var trip: TripRepository = SupabaseTripRepository()
    // Real shared backend — public.night_plans exists and is live in
    // Supabase (schema.sql), same auth-gated pattern as trips. Guest mode
    // can't read/write plans (RLS scopes everything to auth.uid()).
    nonisolated(unsafe) static var plan: PlanRepository = SupabasePlanRepository()
    nonisolated(unsafe) static var post: PostRepository = SupabasePostRepository()
    nonisolated(unsafe) static var greekLife: GreekLifeRepository = SupabaseGreekLifeRepository()
    nonisolated(unsafe) static var profileAffiliation: ProfileAffiliationRepository = SupabaseProfileAffiliationRepository()
    nonisolated(unsafe) static var chapterChat: ChapterChatRepository = SupabaseChapterChatRepository()
    nonisolated(unsafe) static var chapterEvents: ChapterEventsRepository = SupabaseChapterEventsRepository()
    nonisolated(unsafe) static var birthdate: BirthdateRepository = SupabaseBirthdateRepository()
    nonisolated(unsafe) static var venueCheckin: VenueCheckinRepository = SupabaseVenueCheckinRepository()
    nonisolated(unsafe) static var stadium: StadiumRepository = SupabaseStadiumRepository()
    nonisolated(unsafe) static var homeAddress: HomeAddressRepository = SupabaseHomeAddressRepository()
    nonisolated(unsafe) static var displayName: DisplayNameRepository = SupabaseDisplayNameRepository()
    nonisolated(unsafe) static var chapterMembers: ChapterMembersRepository = SupabaseChapterMembersRepository()
}
