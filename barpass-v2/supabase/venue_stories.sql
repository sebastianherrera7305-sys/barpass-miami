-- ═══════════════════════════════════════════════════════════════════
-- VENUE STORIES — "where is everybody tonight"
-- ═══════════════════════════════════════════════════════════════════
-- Idempotent, safe to re-run. Creates NO new table.
--
-- The question Google cannot answer is not "is this bar good", it is
-- "where is everybody right now". Answering it needs people posting from
-- inside a venue tonight — which is exactly what public.venue_media
-- already collects (venue_media.sql). A story is therefore not a new
-- object: it is a venue_media row *inside its night*. Everything below is
-- two views and two small functions on top of the rows that exist.
--
-- Nothing here deletes anything. A story stops being a story when its
-- night ends; the underlying venue_media row stays forever and keeps
-- feeding the venue's photo grid. "Expiry" is a read-time predicate, not
-- a cron job that destroys a venue's archive.
--
--
-- ── WHY THE WINDOW IS "THE NIGHT" AND NOT 24 HOURS ────────────────
-- A rolling 24h window is wrong for nightlife in both directions. At
-- 11pm Saturday it would still be showing Friday 11pm frames — the
-- answer to "where is everybody" from a different night, which is worse
-- than no answer. And a 2am post belongs to the night that started the
-- evening before, not to the calendar day the clock has rolled into.
--
-- So a story lives until the end of the night it was posted in, where a
-- night ends at 6:00 AM local time. That is the same past-midnight rule
-- VenueTimeStatus already uses on the client for opening hours, and it
-- means: post at 11pm Friday → visible until 6am Saturday; post at 2am
-- Saturday → still Friday's night, also visible until 6am Saturday; post
-- at 7am → a new (empty) night, which is correct, nobody is out.
--
-- Local to the VENUE, not to the reader: venues.timezone exists
-- (venue_geography_schema.sql) and a Miami night and a Chicago night do
-- not end at the same instant.
--
--
-- ── THE PRIVACY DECISION ──────────────────────────────────────────
-- Stated plainly: NO viewer ever learns who posted a story. Not anon,
-- not a signed-in user. The only person who can identify a story's
-- author is the author (is_mine below).
--
-- The product wants social proof. Social proof is "12 people are here",
-- and that is a COUNT — it never required a roster. Full attribution, on
-- a college campus, means any account can open a venue page at 1am and
-- read a named list of who is standing in that bar right now. That is
-- precisely the exposure that was already closed once, when
-- venue_media.user_id turned out to be readable by anon and let anyone
-- with the public key reconstruct a person's location history
-- (security_hardening_2026_09_09.sql). Re-attaching a name to the same
-- row through a "stories" feature would be that leak returning with a
-- nicer UI.
--
-- The honest middle — and it is a real middle, not a refusal — is that
-- frames are GROUPED but not NAMED. Each story carries `poster_seq`, a
-- number that is stable only within one venue on one night, assigned in
-- the order people first posted. It lets the viewer see that four frames
-- came from the same person (so the crowd count cannot be inflated by
-- one person posting ten times) and lets the client play them as one
-- person's run, which is what makes it read as a story rather than a
-- grid. It is a dense_rank, not a hash of a user id: there is no secret
-- to leak and nothing to brute force, and because it restarts every
-- night and every venue it cannot be joined across either. "Guest 3 at
-- Kiki tonight" is unlinkable to "Guest 3 at Kiki tomorrow".
--
-- Two consequences this file enforces rather than assumes:
--   1. user_id is revoked from `authenticated` too, not only `anon`.
--      The 2026-09-09 fix revoked it from anon alone, which left the
--      whole location history readable by anyone willing to sign up —
--      a free, instant account. Signup is not an authorization boundary.
--   2. The views are SECURITY DEFINER (security_invoker = false), the
--      same pattern venue_price_stats / venue_age_effective use, so the
--      aggregate can read a column its callers cannot.
--
-- Owner-only delete is unaffected: the DELETE policy on venue_media
-- compares user_id server-side, inside the policy, where column grants
-- do not apply.
--
--
-- ── KNOWN LIMIT, WRITTEN DOWN RATHER THAN GUESSED AWAY ────────────
-- A story asserts presence ("posted from here") but nothing in this file
-- proves the poster was physically at the venue — venue_media has no
-- check-in requirement. public.venue_checkins is the obvious next step
-- (require a check-in at the same venue in the same night before a row
-- counts toward the pulse). It is deliberately NOT done here because it
-- would silently zero out the 6 rows that exist today and make the
-- feature look dead. Until then the UI must say "posted from here",
-- which is exactly what the row supports, and never "12 people are here".


-- ═══════════════════════════════════════════════════════════════════
-- 1. WHAT NIGHT IS IT
-- ═══════════════════════════════════════════════════════════════════

-- The night a moment belongs to, as a date: shift the venue's local wall
-- clock back 6 hours, then take the calendar day. 2am Saturday shifts to
-- 8pm Friday → the Friday night.
create or replace function public.bp_night_of(p_ts timestamptz, p_tz text)
returns date
language sql
stable
set search_path = public
as $$
  select (((p_ts at time zone coalesce(nullif(p_tz, ''), 'America/New_York'))
           - interval '6 hours')::date);
$$;

-- The instant that night is over: 6:00 AM local on the following morning.
create or replace function public.bp_night_end(p_night date, p_tz text)
returns timestamptz
language sql
stable
set search_path = public
as $$
  select (((p_night + 1)::timestamp + interval '6 hours')
          at time zone coalesce(nullif(p_tz, ''), 'America/New_York'));
$$;


-- ═══════════════════════════════════════════════════════════════════
-- 2. CLOSE THE user_id LEAK PROPERLY
-- ═══════════════════════════════════════════════════════════════════
-- anon was revoked on 2026-09-09; authenticated was not. Both now.
revoke select (user_id) on public.venue_media from anon;
revoke select (user_id) on public.venue_media from authenticated;

-- Inserting still needs the column (the INSERT policy checks
-- user_id = auth.uid()), so make sure that grant is intact.
grant insert (venue_id, user_id, media_url, media_type) on public.venue_media to authenticated;

-- Clients must now name their columns; `select=*` on venue_media fails
-- for both roles, by design. The iOS repository was changed to an
-- explicit column list in the same change as this file.


-- ═══════════════════════════════════════════════════════════════════
-- 3. THE STORIES VIEW
-- ═══════════════════════════════════════════════════════════════════
-- One row per live story. No user_id, ever.
drop view if exists public.venue_story_pulse;
drop view if exists public.venue_stories;

create view public.venue_stories as
with recent as (
    -- A night is at most 24h long, so nothing older than ~30h can still
    -- be live. This bound is what lets venue_media_venue_idx do the work
    -- instead of a full scan.
    select m.id,
           m.venue_id,
           m.user_id,
           m.media_url,
           m.media_type,
           m.created_at,
           public.bp_night_of(m.created_at, v.timezone) as night_date,
           v.timezone                                   as venue_timezone
      from public.venue_media m
      join public.venues v on v.id = m.venue_id
     where m.created_at > now() - interval '30 hours'
),
live as (
    -- Only the night still in progress survives this filter, so every
    -- surviving row for a venue belongs to the same night_date.
    select r.*, public.bp_night_end(r.night_date, r.venue_timezone) as expires_at
      from recent r
     where public.bp_night_end(r.night_date, r.venue_timezone) > now()
),
grouped as (
    select l.*,
           min(l.created_at) over (partition by l.venue_id, l.user_id) as poster_first_at
      from live l
)
select g.id,
       g.venue_id,
       g.media_url,
       g.media_type,
       g.created_at,
       g.night_date,
       g.expires_at,
       -- Stable only within (venue, night). Restarts every night, so it
       -- cannot be joined across nights or across venues.
       dense_rank() over (
           partition by g.venue_id
           order by g.poster_first_at, g.user_id
       )::int as poster_seq,
       -- The one identity claim we make, and it is only ever about the
       -- caller themselves.
       coalesce(g.user_id = auth.uid(), false) as is_mine
  from grouped g;

-- Definer, like the other aggregates: the view reads user_id so its
-- callers don't have to be able to.
alter view public.venue_stories set (security_invoker = false);


-- ═══════════════════════════════════════════════════════════════════
-- 4. THE CROWD SIGNAL
-- ═══════════════════════════════════════════════════════════════════
-- What a venue card needs: a number and a frame. Never a roster.
-- poster_seq is a contiguous dense_rank, so its max IS the number of
-- distinct people who posted — computed without the aggregate ever
-- emitting, or the caller ever seeing, who they are.
create view public.venue_story_pulse as
select s.venue_id,
       count(*)::int                                          as story_count,
       max(s.poster_seq)::int                                 as poster_count,
       max(s.created_at)                                      as latest_at,
       min(s.night_date)                                      as night_date,
       (array_agg(s.media_url  order by s.created_at desc))[1] as latest_media_url,
       (array_agg(s.media_type order by s.created_at desc))[1] as latest_media_type
  from public.venue_stories s
 group by s.venue_id;

alter view public.venue_story_pulse set (security_invoker = false);

grant select on public.venue_stories     to anon, authenticated;
grant select on public.venue_story_pulse to anon, authenticated;

-- The view filters on created_at across all venues (the feed asks for
-- every venue's pulse in one request), which the existing
-- (venue_id, created_at desc) index cannot serve on its own.
create index if not exists venue_media_created_idx
    on public.venue_media (created_at desc);


-- PostgREST caches the schema; without this the two new views 404 over
-- the REST API until the next restart.
notify pgrst, 'reload schema';


-- ═══════════════════════════════════════════════════════════════════
-- 5. VERIFICATION
-- ═══════════════════════════════════════════════════════════════════
-- Run these after applying. Every one of them is about privacy except
-- the first two.
--
-- (a) The night function does the past-midnight thing. Expect the first
--     three to be the same Friday date, and the fourth to be Saturday.
--
--   select public.bp_night_of('2026-09-12 23:00-04'::timestamptz, 'America/New_York'),
--          public.bp_night_of('2026-09-13 02:00-04'::timestamptz, 'America/New_York'),
--          public.bp_night_of('2026-09-13 05:59-04'::timestamptz, 'America/New_York'),
--          public.bp_night_of('2026-09-13 06:01-04'::timestamptz, 'America/New_York');
--
-- (b) The pulse is a count, and it matches the stories.
--
--   select p.venue_id, v.name, p.story_count, p.poster_count, p.latest_at
--     from public.venue_story_pulse p join public.venues v on v.id = p.venue_id
--    order by p.poster_count desc;
--
-- (c) The view exposes no identifying column at all. Expect zero rows.
--
--   select column_name from information_schema.columns
--    where table_schema = 'public' and table_name in ('venue_stories','venue_story_pulse')
--      and column_name in ('user_id','email','profile_id','poster_id');
--
-- (d) Neither public role can read user_id from the base table any more.
--     Expect zero rows.
--
--   select grantee, privilege_type, column_name
--     from information_schema.column_privileges
--    where table_schema = 'public' and table_name = 'venue_media'
--      and column_name = 'user_id' and privilege_type = 'SELECT'
--      and grantee in ('anon','authenticated');
--
-- (e) Same thing as the database sees it — run AS anon. Expect
--     "permission denied for column user_id", not a result set.
--
--   set local role anon;
--   select user_id from public.venue_media limit 1;
--   reset role;
--
-- (f) LIVE, over the wire, with the ANON key. Substitute <PROJECT_REF>
--     and $SUPABASE_ANON_KEY (never paste the key into a file).
--
--     -- must return rows with NO user_id field anywhere:
--   curl -s "https://<PROJECT_REF>.supabase.co/rest/v1/venue_stories?select=*&limit=5" \
--        -H "apikey: $SUPABASE_ANON_KEY" -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
--      | grep -c user_id                      # expect: 0
--
--     -- must return a count and nothing else identifying:
--   curl -s "https://<PROJECT_REF>.supabase.co/rest/v1/venue_story_pulse?select=venue_id,story_count,poster_count" \
--        -H "apikey: $SUPABASE_ANON_KEY" -H "Authorization: Bearer $SUPABASE_ANON_KEY"
--
--     -- asking for the column by name must be REFUSED, not empty:
--   curl -s "https://<PROJECT_REF>.supabase.co/rest/v1/venue_media?select=user_id&limit=1" \
--        -H "apikey: $SUPABASE_ANON_KEY" -H "Authorization: Bearer $SUPABASE_ANON_KEY"
--        # expect: {"code":"42501", ... "permission denied for column user_id"}
--
--     -- and the star select must be refused too (this is why the iOS
--     -- repository now names its columns):
--   curl -s "https://<PROJECT_REF>.supabase.co/rest/v1/venue_media?select=*&limit=1" \
--        -H "apikey: $SUPABASE_ANON_KEY" -H "Authorization: Bearer $SUPABASE_ANON_KEY"
--        # expect: 42501
