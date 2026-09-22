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
    nonisolated(unsafe) static var tripMembers: TripMembersRepository = SupabaseTripMembersRepository()

    /// Reportar y silenciar sobre las historias públicas
    /// (supabase/media_moderation.sql). Todo se direcciona por id de MEDIA y
    /// nunca por autor: el cliente no puede leer `venue_media.user_id` — esa
    /// invariante es la que hace que una foto pública no delate a quien la
    /// subió, y la moderación se construyó para no romperla.
    nonisolated(unsafe) static var mediaReport: MediaReportRepository = SupabaseMediaReportRepository()

    /// El beacon de seguridad (supabase/safety_beacon.sql). La audiencia NO
    /// es el roster del trip: es la intersección entre tus amigos aceptados y
    /// ese roster. Razón dura — la policy de UPDATE de `trips` deja que
    /// cualquier miembro reescriba `member_ids`, y el código de invitación se
    /// reenvía y se postea. Una audiencia definida por ese array es una
    /// audiencia a la que cualquiera se suma solo.
    nonisolated(unsafe) static var safetyBeacon: SafetyBeaconRepository = SupabaseSafetyBeaconRepository()
    nonisolated(unsafe) static var venueMedia: VenueMediaRepository = SupabaseVenueMediaRepository()

    /// Grupo efímero + chat efímero + "buscar al líder" con push
    /// (supabase/safety_groups.sql). A diferencia del beacon, esto SÍ tiene push.
    nonisolated(unsafe) static var safetyGroup: SafetyGroupRepository = SupabaseSafetyGroupRepository()

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

    /// La carta del local (venue_menu_items): pública, de sólo lectura, con
    /// la procedencia de cada precio adentro de cada fila.
    nonisolated(unsafe) static var venueMenu: VenueMenuRepository = SupabaseVenueMenuRepository()

    /// "¿Qué podemos hacer mejor?" — write-only (supabase/app_feedback.sql).
    nonisolated(unsafe) static var feedback: FeedbackRepository = SupabaseFeedbackRepository()
}
