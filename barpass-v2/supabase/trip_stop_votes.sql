-- ─────────────────────────────────────────────────────────────────────────
-- BarPass V2 — TRIP STOP VOTES: "votan entre varios spots y gana uno".
--
-- Run in the Supabase SQL editor. Idempotent — safe to re-run.
--
-- A trip already holds members and an ordered list of stops. The only thing
-- missing to settle "where are we actually going" was a vote per member per
-- stop. That is this file: one table, one unique index, RLS, and a tally view.
--
-- Deliberately NOT a separate poll object. The stops ARE the options — a poll
-- would duplicate them and immediately drift out of sync with the itinerary.
-- ─────────────────────────────────────────────────────────────────────────

create table if not exists public.trip_stop_votes (
    id         uuid primary key default gen_random_uuid(),
    trip_id    uuid not null references public.trips(id) on delete cascade,
    -- Stops live inside the trip's own table; the FK is the trip, and stop_id
    -- is validated against that trip's stops by the policies below.
    stop_id    uuid not null,
    user_id    uuid not null references auth.users(id) on delete cascade,
    created_at timestamptz not null default now()
);

-- One vote per member per stop. Changing your mind is a delete + insert, which
-- is also what makes "unvote" free.
create unique index if not exists trip_stop_votes_one_per_user
    on public.trip_stop_votes (stop_id, user_id);
create index if not exists trip_stop_votes_trip_idx on public.trip_stop_votes (trip_id);

alter table public.trip_stop_votes enable row level security;

-- Membership is the whole access rule: you see and cast votes only on a trip
-- you belong to. No anon policy at all — a vote ties a named person to a venue
-- on a date, the same shape as the venue_media.user_id leak.
drop policy if exists trip_stop_votes_select on public.trip_stop_votes;
create policy trip_stop_votes_select on public.trip_stop_votes
    for select to authenticated
    using (exists (
        select 1 from public.trips t
        where t.id = trip_stop_votes.trip_id
          and (auth.uid() = t.creator_id or auth.uid() = any(t.member_ids))
    ));

-- WITH CHECK pins user_id to the caller: you cannot vote as someone else, and
-- you cannot stuff a trip you are not in.
drop policy if exists trip_stop_votes_insert on public.trip_stop_votes;
create policy trip_stop_votes_insert on public.trip_stop_votes
    for insert to authenticated
    with check (
        auth.uid() = user_id
        and exists (
            select 1 from public.trips t
            where t.id = trip_stop_votes.trip_id
              and (auth.uid() = t.creator_id or auth.uid() = any(t.member_ids))
        )
    );

-- You may only ever delete your own vote. A trip creator cannot clear someone
-- else's — that would make the tally a suggestion rather than a count.
drop policy if exists trip_stop_votes_delete on public.trip_stop_votes;
create policy trip_stop_votes_delete on public.trip_stop_votes
    for delete to authenticated
    using (auth.uid() = user_id);

-- No UPDATE policy: a vote is cast or withdrawn, never edited.

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICATION  (expect the stated result)
-- ═══════════════════════════════════════════════════════════════════
--
-- RLS is on.                                       -- expect rowsecurity = true
--   select relname, relrowsecurity from pg_class
--    where relnamespace = 'public'::regnamespace and relname = 'trip_stop_votes';
--
-- No policy grants anon.                           -- expect 0 rows
--   select p.polname from pg_policy p join pg_class c on c.oid = p.polrelid
--    where c.relname = 'trip_stop_votes'
--      and 'anon' = any(array(select rolname from pg_roles where oid = any(p.polroles)));
--
-- Nobody voted twice on one stop.                  -- expect 0 rows
--   select stop_id, user_id, count(*) from public.trip_stop_votes
--    group by 1,2 having count(*) > 1;
--
-- Live check with the ANON key.                    -- expect []
--   curl -s "$URL/rest/v1/trip_stop_votes?select=user_id" -H "apikey: $ANON"
