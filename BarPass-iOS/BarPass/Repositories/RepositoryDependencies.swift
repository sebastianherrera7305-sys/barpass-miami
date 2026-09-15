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

    /// Votes on a trip's stops — "votan entre varios spots y gana uno".
    nonisolated(unsafe) static var tripStopVote: TripStopVoteRepository = SupabaseTripStopVoteRepository()
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
    nonisolated(unsafe) static var venueMedia: VenueMediaRepository = SupabaseVenueMediaRepository()

    /// Stories — the same venue_media rows, read inside the night they were
    /// posted in (supabase/venue_stories.sql). No new table, no new upload
    /// path; posting a photo after a check-in already creates one.
    nonisolated(unsafe) static var venueStory: VenueStoryRepository = SupabaseVenueStoryRepository()

    /// The friend graph (barpass-v2/supabase/friend_graph_schema.sql):
    /// symmetric, mutual-accept friendships plus discovery, blocking, and
    /// "who's out tonight". Every call is a SECURITY DEFINER RPC — the
    /// underlying tables have no client grants worth reading.
    nonisolated(unsafe) static var friends: FriendsRepository = SupabaseFriendsRepository()

    /// 1:1 DMs between accepted friends — same encrypted-at-rest,
    /// RPC-only, rate-limited, reportable design as the chapter chat.
    nonisolated(unsafe) static var friendChat: FriendChatRepository = SupabaseFriendChatRepository()

    /// Host-run nights (free RSVP tiers, waiting list, door). Writes go
    /// through barpass-v2's /api/host-events routes, not PostgREST — the RPCs
    /// behind them hold the locks and rate limits.
    nonisolated(unsafe) static var hostEvent: HostEventRepository = BarPassHostEventRepository()
}
