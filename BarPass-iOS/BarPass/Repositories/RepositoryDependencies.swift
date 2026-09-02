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
    // Supabase (schema.sql). RLS scopes rows to auth.uid(), so a guest
    // session can't read/write there — CompositePlanRepository (below)
    // routes guests to LocalPlanRepository instead, a fix landed
    // 2026-09-02: this doc comment used to claim that fallback while
    // `plan` was hardcoded straight to Supabase, so guests actually got
    // zero persistence.
    nonisolated(unsafe) static var plan: PlanRepository = CompositePlanRepository()
    // Real shared backend — public.plan_conversations (schema.sql), same
    // jsonb-blob-per-row and guest-fallback pattern as `plan` above (see
    // CLAUDE.md → "Plan Chat Architecture").
    nonisolated(unsafe) static var conversation: ConversationRepository = CompositeConversationRepository()
    nonisolated(unsafe) static var post: PostRepository = SupabasePostRepository()
    nonisolated(unsafe) static var greekLife: GreekLifeRepository = SupabaseGreekLifeRepository()
    nonisolated(unsafe) static var profileAffiliation: ProfileAffiliationRepository = SupabaseProfileAffiliationRepository()
    nonisolated(unsafe) static var chapterChat: ChapterChatRepository = SupabaseChapterChatRepository()
    nonisolated(unsafe) static var birthdate: BirthdateRepository = SupabaseBirthdateRepository()
    nonisolated(unsafe) static var venueCheckin: VenueCheckinRepository = SupabaseVenueCheckinRepository()
    nonisolated(unsafe) static var stadium: StadiumRepository = SupabaseStadiumRepository()
    nonisolated(unsafe) static var homeAddress: HomeAddressRepository = SupabaseHomeAddressRepository()
}
