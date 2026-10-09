-- ─────────────────────────────────────────────────────────────────────────
-- BarPass — Server-authoritative Trips trust/reputation system.
--
-- Run in the Supabase SQL editor. Idempotent — safe to re-run.
--
-- PREREQS: schema.sql, trips_schema.sql, friend_graph_schema.sql must
-- all be live first.
--
-- Context: the previous reputation system was a JSON file in each
-- device's Application Support directory. The "trust signals" shown to
-- an organizer when someone asked to join a trip reflected only ratings
-- that user had seen on the ORGANIZER's own device — never the other
-- person's real reputation across devices. "Blind reveal" only worked
-- when one device held both halves of a rating pair, which was almost
-- never. The audit flagged this as misleading.
--
-- This migration replaces it with:
--   - trip_completions: a server-side snapshot of who was a member when
--     a trip closed. Rating windows are frozen at completion time.
--   - trip_ratings: append-only mutual peer ratings. Blind-reveal is a
--     SELECT-time computation (your score is only visible after the
--     other person also rated you), so a rater who sees the counter-score
--     cannot adjust their own.
--   - complete_trip() RPC: the ONLY path to flip trips.status to
--     'completed'. Takes a snapshot of the member list and opens a
--     14-day rating window.
--   - submit_trip_rating() RPC: forces rater_id = auth.uid(), checks
--     membership against the frozen snapshot, caps 20/day/user.
--   - get_user_reputation() RPC: aggregates revealed ratings. Only
--     readable by people who share a trip or pending request with the
--     target — strangers cannot scrape the reputation surface.
--
-- Design decisions worth stating:
--   - Immutable ratings. No UPDATE/DELETE policy. Once you submit,
--     you cannot change it after seeing the other side. The whole point
--     of "blind reveal" relies on this.
--   - Snapshot frozen at completion. If an organizer removes you AFTER
--     completion, your rating still counts (you were in the room when
--     the trip ended). This is intentional and auditable; the alternative
--     (dynamic membership check at rating time) opens retaliation vectors.
--   - A trip of one organizer and three friends who went to three bars
--     counts as ONE completed trip toward each person, not three.
--   - This is v1 — the known gap is that two paired bot accounts can
--     create N trips with each other and both claim 'verified'. v1.5
--     will add check-in-based attendance proof (requires a stop-level
--     venue_checkins row inside the trip window). We ship v1 as a
--     Miami-only pilot with the explicit expectation that real abuse
--     evidence drives the v1.5 priority, not speculation.
-- ─────────────────────────────────────────────────────────────────────────

-- 1. trip_completions — the snapshot that freezes who can rate whom.
create table if not exists public.trip_completions (
  trip_id          uuid primary key references public.trips(id) on delete cascade,
  completed_at     timestamptz not null default now(),
  completed_by     uuid not null references auth.users(id) on delete cascade,
  -- creator_id + every entry of member_ids at completion time, deduped.
  -- Everyone in this array is eligible to rate (or be rated by) everyone
  -- else in the array for this trip.
  member_snapshot  uuid[] not null,
  -- Hard-coded 14-day rating window. A trip's "did they show up / were
  -- they a problem" judgment should be timely — months later it's
  -- noise. Also prevents an organizer from re-opening a dead trip to
  -- settle a grudge.
  rating_closes_at timestamptz not null default (now() + interval '14 days'),
  constraint trip_completions_has_members check (array_length(member_snapshot, 1) >= 2)
);

create index if not exists trip_completions_member_snapshot_idx
  on public.trip_completions using gin (member_snapshot);

alter table public.trip_completions enable row level security;

drop policy if exists "trip_completions readable by participants" on public.trip_completions;
create policy "trip_completions readable by participants"
  on public.trip_completions
  for select to authenticated
  using (auth.uid() = any(member_snapshot));

-- No INSERT/UPDATE/DELETE policy. Only complete_trip() writes this table.


-- 2. trip_ratings — append-only mutual peer ratings.
create table if not exists public.trip_ratings (
  id          uuid primary key default gen_random_uuid(),
  trip_id     uuid not null references public.trips(id) on delete cascade,
  scope_kind  text not null check (scope_kind in ('trip', 'stop')),
  -- For scope_kind='trip', scope_id = trip_id. For scope_kind='stop',
  -- scope_id = a stop UUID from the trips.stops jsonb array. v1 does
  -- not validate that the stop UUID actually belongs to the trip; this
  -- is a known gap documented in the follow-up list.
  scope_id    uuid not null,
  rater_id    uuid not null references auth.users(id) on delete cascade,
  ratee_id    uuid not null references auth.users(id) on delete cascade,
  score       smallint not null check (score between 1 and 5),
  tags        text[] not null default '{}'
              check (array_length(tags, 1) is null or array_length(tags, 1) <= 3),
  created_at  timestamptz not null default now(),

  constraint trip_ratings_no_self check (rater_id <> ratee_id),
  constraint trip_ratings_unique_pair unique (scope_kind, scope_id, rater_id, ratee_id)
);

create index if not exists trip_ratings_trip_idx  on public.trip_ratings (trip_id);
create index if not exists trip_ratings_ratee_idx on public.trip_ratings (ratee_id);
create index if not exists trip_ratings_rater_rate_limit_idx
  on public.trip_ratings (rater_id, created_at desc);

alter table public.trip_ratings enable row level security;

drop policy if exists "trip_ratings readable by participants" on public.trip_ratings;
create policy "trip_ratings readable by participants"
  on public.trip_ratings
  for select to authenticated
  using (auth.uid() = rater_id or auth.uid() = ratee_id);

-- No INSERT policy: all inserts via submit_trip_rating() with rater_id = auth.uid().
-- No UPDATE policy: ratings are immutable.
-- No DELETE policy: audit trail. Admin cleanup via service-role script if ever needed.


-- ─────────────────────────────────────────────────────────────────────────
-- 3. complete_trip(trip_id) — the ONLY path to status='completed'.
-- ─────────────────────────────────────────────────────────────────────────
-- Flipping status to 'completed' used to be a plain client PATCH (any
-- member could do it via the generic trips UPDATE policy). After this
-- migration ships AND the iOS client stops writing status, revoke the
-- column-level grant with:
--
--   revoke update (status) on public.trips from authenticated;
--
-- but ONLY after proving by behavior (not just by inspecting grants)
-- that the old client path is dead — see the memory note on the
-- Postgres column-revoke-under-broad-table-GRANT trap. That revoke is
-- deliberately NOT in this file: it's a separate deploy that cuts off
-- old TestFlight builds.

drop function if exists public.complete_trip(uuid);

create or replace function public.complete_trip(p_trip_id uuid)
returns public.trips
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me    uuid := auth.uid();
  v_trip  public.trips;
  v_snap  uuid[];
begin
  if v_me is null then raise exception 'not_authenticated'; end if;

  select * into v_trip from public.trips where id = p_trip_id for update;
  if not found then raise exception 'trip_not_found'; end if;

  -- Already completed? Return idempotently. Second caller sees the
  -- same snapshot/window as the first — safe for retry.
  if v_trip.status = 'completed' then
    return v_trip;
  end if;

  if v_me <> v_trip.creator_id
     and not (v_me = any(coalesce(v_trip.co_organizer_ids, '{}'::uuid[])))
  then
    raise exception 'not_organizer';
  end if;

  v_snap := (
    select array_agg(distinct uid)
      from unnest(array[v_trip.creator_id] || coalesce(v_trip.member_ids, '{}'::uuid[])) uid
     where uid is not null
  );

  if array_length(v_snap, 1) < 2 then
    raise exception 'need_two_members';
  end if;

  update public.trips set status = 'completed' where id = p_trip_id;

  insert into public.trip_completions (trip_id, completed_by, member_snapshot)
  values (p_trip_id, v_me, v_snap);

  select * into v_trip from public.trips where id = p_trip_id;
  return v_trip;
end;
$$;

grant execute on function public.complete_trip(uuid) to authenticated;
revoke execute on function public.complete_trip(uuid) from public, anon;


-- ─────────────────────────────────────────────────────────────────────────
-- 4. submit_trip_rating(trip_id, scope_kind, scope_id, ratee_id, score, tags)
-- ─────────────────────────────────────────────────────────────────────────
-- Checks the client cannot bypass (every one of these is a real
-- manipulation vector, not just input validation):
--   - rater_id is forced to auth.uid() — no client-supplied rater claim
--   - score ∈ [1,5], tags ≤ 3 — bounded surface
--   - scope_kind='trip' implies scope_id = p_trip_id — can't retarget
--   - trip must be completed — can't rate ongoing or planned trips
--   - now() must be inside rating_closes_at — can't resurrect dead trips
--   - rater AND ratee must be in the frozen member_snapshot — can't
--     rate someone who was never there, and can't rate from outside
--     the room
--   - no self-rating — rater_id <> ratee_id (CHECK + explicit error)
--   - at most 20 ratings per rater per 24h — caps a compromised account
--   - unique on (scope_kind, scope_id, rater, ratee) — one rating per pair
--     per scope, enforced atomically by the index

drop function if exists public.submit_trip_rating(uuid, text, uuid, uuid, smallint, text[]);

create or replace function public.submit_trip_rating(
  p_trip_id    uuid,
  p_scope_kind text,
  p_scope_id   uuid,
  p_ratee_id   uuid,
  p_score      smallint,
  p_tags       text[]
)
returns public.trip_ratings
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me          uuid := auth.uid();
  v_completion  public.trip_completions;
  v_recent      int;
  v_row         public.trip_ratings;
begin
  if v_me is null then raise exception 'not_authenticated'; end if;
  if v_me = p_ratee_id then raise exception 'cannot_rate_self'; end if;
  if p_score is null or p_score < 1 or p_score > 5 then raise exception 'invalid_score'; end if;
  if p_tags is not null and array_length(p_tags, 1) > 3 then raise exception 'too_many_tags'; end if;
  if p_scope_kind not in ('trip', 'stop') then raise exception 'invalid_scope_kind'; end if;
  if p_scope_kind = 'trip' and p_scope_id <> p_trip_id then raise exception 'scope_id_mismatch'; end if;

  select * into v_completion from public.trip_completions where trip_id = p_trip_id;
  if not found then raise exception 'trip_not_completed'; end if;
  if now() > v_completion.rating_closes_at then raise exception 'rating_window_closed'; end if;

  if not (v_me = any(v_completion.member_snapshot)) then raise exception 'not_a_member'; end if;
  if not (p_ratee_id = any(v_completion.member_snapshot)) then raise exception 'ratee_not_a_member'; end if;

  -- Rate limit — a compromised account can't spray scores.
  select count(*) into v_recent
    from public.trip_ratings
   where rater_id = v_me
     and created_at > now() - interval '24 hours';
  if v_recent >= 20 then raise exception 'rate_limited'; end if;

  begin
    insert into public.trip_ratings (trip_id, scope_kind, scope_id, rater_id, ratee_id, score, tags)
    values (p_trip_id, p_scope_kind, p_scope_id, v_me, p_ratee_id, p_score, coalesce(p_tags, '{}'))
    returning * into v_row;
  exception when unique_violation then
    raise exception 'already_rated';
  end;

  return v_row;
end;
$$;

grant execute on function public.submit_trip_rating(uuid, text, uuid, uuid, smallint, text[]) to authenticated;
revoke execute on function public.submit_trip_rating(uuid, text, uuid, uuid, smallint, text[]) from public, anon;


-- ─────────────────────────────────────────────────────────────────────────
-- 5. get_user_reputation(user_id)
-- ─────────────────────────────────────────────────────────────────────────
-- Visibility: self, or someone you share a trip with (as creator or
-- member) or have a pending/accepted friend request with. Strangers
-- cannot scrape — this closes the "walk every uid to build a profile"
-- vector.
--
-- avg_score and ratings_count only reflect REVEALED ratings — a rating
-- is revealed only when the reciprocal rating exists on the same
-- (trip, scope_kind, scope_id). Blind-reveal at read time means a
-- rater who sees the counter-score cannot adjust their own (no UPDATE
-- policy anyway, but this is why the architecture works end-to-end).

drop function if exists public.get_user_reputation(uuid);

create or replace function public.get_user_reputation(p_user_id uuid)
returns table(
  user_id         uuid,
  completed_trips int,
  avg_score       numeric,
  ratings_count   int,
  badge           text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me      uuid := auth.uid();
  v_shares  boolean;
  v_badge   text;
  v_count   int;
  v_avg     numeric;
  v_rc      int;
begin
  if v_me is null then raise exception 'not_authenticated'; end if;

  if v_me <> p_user_id then
    select exists(
      select 1 from public.trips t
       where (t.creator_id = v_me and p_user_id = any(coalesce(t.member_ids, '{}'::uuid[])))
          or (t.creator_id = p_user_id and v_me = any(coalesce(t.member_ids, '{}'::uuid[])))
          or (v_me = any(coalesce(t.member_ids, '{}'::uuid[]))
              and p_user_id = any(coalesce(t.member_ids, '{}'::uuid[])))
    ) or exists(
      select 1 from public.friendships f
       where ((f.user_a = v_me and f.user_b = p_user_id)
           or (f.user_a = p_user_id and f.user_b = v_me))
         and f.status in ('accepted', 'pending')
    )
    into v_shares;
    if not coalesce(v_shares, false) then raise exception 'not_visible'; end if;
  end if;

  select count(*)::int into v_count
    from public.trip_completions tc
   where p_user_id = any(tc.member_snapshot);

  with revealed as (
    select r.score
      from public.trip_ratings r
     where r.ratee_id = p_user_id
       and exists(
         select 1 from public.trip_ratings r2
          where r2.trip_id    = r.trip_id
            and r2.scope_kind = r.scope_kind
            and r2.scope_id   = r.scope_id
            and r2.rater_id   = r.ratee_id
            and r2.ratee_id   = r.rater_id
       )
  )
  select count(*)::int, round(avg(score)::numeric, 2)
    into v_rc, v_avg
    from revealed;

  v_badge := case
    when v_count >= 10 then 'verified'
    when v_count >= 3  then 'trusted_planner'
    else                     'new'
  end;

  return query select p_user_id, v_count, v_avg, coalesce(v_rc, 0), v_badge;
end;
$$;

grant execute on function public.get_user_reputation(uuid) to authenticated;
revoke execute on function public.get_user_reputation(uuid) from public, anon;


notify pgrst, 'reload schema';


-- ═══════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════
--
-- Run as two signed-in test users A and B who are both in a trip.
--
-- 1. Non-organizer cannot complete:
--    select * from public.complete_trip('<trip from B as member>');
--    -- expect: ERROR not_organizer
--
-- 2. Solo trip cannot complete:
--    (make a trip with just A as member_ids=[])
--    select * from public.complete_trip('<solo trip>');
--    -- expect: ERROR need_two_members
--
-- 3. Normal complete:
--    select * from public.complete_trip('<2-member trip>');
--    -- expect: row returned with status='completed'; trip_completions row exists
--
-- 4. Idempotent complete:
--    select * from public.complete_trip('<same trip>');
--    -- expect: same row returned; no second trip_completions row
--
-- 5. Rating cannot be self:
--    select * from public.submit_trip_rating('<trip>', 'trip', '<trip>', auth.uid(), 5, '{}');
--    -- expect: ERROR cannot_rate_self
--
-- 6. Rating a non-member:
--    select * from public.submit_trip_rating('<trip>', 'trip', '<trip>', '<stranger uid>', 5, '{}');
--    -- expect: ERROR ratee_not_a_member
--
-- 7. Blind reveal: A rates B 5 stars.
--    (as A) select * from public.submit_trip_rating('<trip>', 'trip', '<trip>', '<B>', 5, '{}');
--    (as A) select * from public.get_user_reputation('<B>');
--    -- expect: ratings_count=0, avg_score=null (not revealed yet)
--    (as B) select * from public.submit_trip_rating('<trip>', 'trip', '<trip>', '<A>', 4, '{}');
--    (as A) select * from public.get_user_reputation('<B>');
--    -- expect: ratings_count=1, avg_score=5.00 (reciprocal exists)
--    (as B) select * from public.get_user_reputation('<A>');
--    -- expect: ratings_count=1, avg_score=4.00
--
-- 8. Duplicate rating:
--    (same insert as above) -- expect: ERROR already_rated
--
-- 9. Direct insert (bypassing RPC) is refused:
--    insert into public.trip_ratings (trip_id, scope_kind, scope_id, rater_id, ratee_id, score)
--      values ('<trip>','trip','<trip>', auth.uid(), '<other>', 5);
--    -- expect: ERROR permission denied / no policy
--
-- 10. Direct update of score refused:
--     update public.trip_ratings set score = 1 where rater_id = auth.uid();
--     -- expect: ERROR permission denied / no policy
--
-- 11. Stranger reputation lookup refused:
--     (as a user with NO shared trip or friendship with X)
--     select * from public.get_user_reputation('<X>');
--     -- expect: ERROR not_visible
--
-- 12. Self reputation always works:
--     select * from public.get_user_reputation(auth.uid());
--     -- expect: row, zero or more completed_trips, badge='new' if < 3
