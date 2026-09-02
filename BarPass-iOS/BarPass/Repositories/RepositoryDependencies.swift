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
    // Real shared backend — public.plan_conversations (schema.sql), same
    // jsonb-blob-per-row pattern as night_plans. Requires a signed-in
    // session; PlanView falls back to LocalConversationRepository for
    // guests (see CLAUDE.md → "Plan Chat Architecture").
    nonisolated(unsafe) static var conversation: ConversationRepository = SupabaseConversationRepository()
    nonisolated(unsafe) static var post: PostRepository = SupabasePostRepository()
    nonisolated(unsafe) static var greekLife: GreekLifeRepository = SupabaseGreekLifeRepository()
    nonisolated(unsafe) static var profileAffiliation: ProfileAffiliationRepository = SupabaseProfileAffiliationRepository()
    nonisolated(unsafe) static var chapterChat: ChapterChatRepository = SupabaseChapterChatRepository()
    nonisolated(unsafe) static var birthdate: BirthdateRepository = SupabaseBirthdateRepository()
    nonisolated(unsafe) static var venueCheckin: VenueCheckinRepository = SupabaseVenueCheckinRepository()
    nonisolated(unsafe) static var stadium: StadiumRepository = SupabaseStadiumRepository()
    nonisolated(unsafe) static var homeAddress: HomeAddressRepository = SupabaseHomeAddressRepository()
}
