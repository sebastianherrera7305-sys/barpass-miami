-- ─────────────────────────────────────────────────────────────────────────
-- BarPass — Custom avatar system for the Social Graph (Friends).
--
-- Run in the Supabase SQL editor. Idempotent — safe to re-run.
--
-- PREREQS (must have been applied first): schema.sql, friend_graph_schema.sql,
-- venue_stories.sql — this file assumes public.profiles, public.friendships,
-- public.bp_blocked_between, public.bp_night_of/bp_night_end, and the four
-- original friend-RPC functions already exist. Running this on a fresh
-- project without friend_graph_schema.sql first will create executable
-- functions with the wrong grant posture.
--
-- `avatar_config` holds the user's illustrated, layered 2D avatar as a
-- small jsonb blob (skin tone, hair style/color, accessory, outfit color,
-- expression — all plain strings, validated client-side against a closed
-- enum, never free text). `avatar_url` is untouched and still wins when
-- both are set (a real uploaded photo is a stronger signal than a drawn
-- avatar) — see AvatarView.swift for the exact precedence rule.
--
-- Scope of this pass: Friends (list_friends / search_profiles /
-- redeem_friend_code / get_friends_out_tonight) only — the actual "Social
-- Graph" surface in this codebase (there is no screen literally named
-- that; Features/Social/SocialView.swift is it). Safety Groups, Safety
-- Beacon, and Host Events attendee lists already carry avatar_url through
-- their own RPCs and are deliberately left for a fast-follow pass rather
-- than touching five SECURITY DEFINER functions in one sweep.
--
-- WHY THE DROP + CREATE PATTERN below (not CREATE OR REPLACE): adding a
-- column to RETURNS TABLE changes the function's composite return type,
-- and Postgres refuses that with "cannot change return type of existing
-- function / Row type defined by OUT parameters is different" — the exact
-- trap already documented in this repo at chapter_events_public.sql. The
-- DROP wipes the EXECUTE grants that friend_graph_schema.sql section 9
-- installed, so we re-grant at the end — otherwise the Friends tab goes
-- 42501 permission denied the moment this runs.
-- ─────────────────────────────────────────────────────────────────────────

alter table public.profiles
  add column if not exists avatar_config jsonb;

-- Shape and size guard: the anon key ships inside the iOS binary, so a
-- client can PATCH this column directly via PostgREST. The file comment
-- promises "closed enum, never free text" — this is the server enforcing
-- that promise. 2 KB is roughly 10× the real payload (6 short enum
-- values); large enough that the enum can grow, small enough to block
-- someone pasting a 10 MB blob into their own profile row.
do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'profiles_avatar_config_object'
       and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles
      add constraint profiles_avatar_config_object
      check (avatar_config is null
             or (jsonb_typeof(avatar_config) = 'object'
                 and pg_column_size(avatar_config) < 2048));
  end if;
end $$;

-- DROP before CREATE: see header. Each function's prior EXECUTE grant to
-- `authenticated` goes with the DROP and must be reinstated at the end
-- of this file.
drop function if exists public.list_friends();
drop function if exists public.search_profiles(text);
drop function if exists public.redeem_friend_code(text);
drop function if exists public.get_friends_out_tonight();

-- Each function below is the EXACT original body from
-- friend_graph_schema.sql, with `avatar_config` added to RETURNS TABLE
-- and to the SELECT list in the same position as avatar_url. No other
-- behavior changes.

create function public.list_friends() returns table (
  user_id uuid,
  display_name text,
  avatar_url text,
  avatar_config jsonb,
  direction text,
  since timestamptz
)
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then return; end if;
  return query
  select
    other.id,
    other.display_name,
    other.avatar_url,
    other.avatar_config,
    case
      when f.status = 'accepted' then 'friend'
      when f.requested_by = v_me then 'outgoing'
      else 'incoming'
    end,
    coalesce(f.responded_at, f.created_at)
  from public.friendships f
  join public.profiles other
    on other.id = case when f.user_a = v_me then f.user_b else f.user_a end
  where (f.user_a = v_me or f.user_b = v_me)
    and not public.bp_blocked_between(v_me, other.id)
  order by (f.status = 'accepted') desc, coalesce(f.responded_at, f.created_at) desc;
end;
$$;

create function public.search_profiles(p_query text) returns table (
  user_id uuid,
  display_name text,
  avatar_url text,
  avatar_config jsonb,
  relation text
)
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := auth.uid();
  v_q text := trim(coalesce(p_query, ''));
begin
  if v_me is null or char_length(v_q) < 2 then return; end if;
  return query
  select
    p.id,
    p.display_name,
    p.avatar_url,
    p.avatar_config,
    coalesce(
      (select case
                when f.status = 'accepted' then 'friend'
                when f.requested_by = v_me then 'outgoing'
                else 'incoming'
              end
         from public.friendships f
        where f.user_a = least(v_me, p.id) and f.user_b = greatest(v_me, p.id)),
      'none')
  from public.profiles p
  where p.id <> v_me
    and p.friend_discoverable
    and p.display_name is not null
    and p.display_name ilike '%' || v_q || '%'
    and not public.bp_blocked_between(v_me, p.id)
  order by
    case when lower(p.display_name) = lower(v_q) then 0
         when lower(p.display_name) like lower(v_q) || '%' then 1
         else 2 end,
    p.display_name
  limit 20;
end;
$$;

create function public.redeem_friend_code(p_code text) returns table (
  user_id uuid,
  display_name text,
  avatar_url text,
  avatar_config jsonb,
  relation text
)
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := auth.uid();
  v_target uuid;
  v_status text;
begin
  if v_me is null then raise exception 'not_authenticated'; end if;
  select p.id into v_target from public.profiles p
   where p.friend_code = upper(regexp_replace(coalesce(p_code, ''), '\s', '', 'g'));
  if v_target is null then raise exception 'code_not_found'; end if;
  if v_target = v_me then raise exception 'code_is_your_own'; end if;

  v_status := public.request_friend(v_target);   -- re-checks blocks, rate limit

  return query
  select p.id, p.display_name, p.avatar_url, p.avatar_config,
         case when v_status = 'accepted' then 'friend' else 'outgoing' end
    from public.profiles p where p.id = v_target;
end;
$$;

create function public.get_friends_out_tonight() returns table (
  user_id uuid,
  display_name text,
  avatar_url text,
  avatar_config jsonb,
  venue_id uuid,
  venue_name text,
  venue_lat double precision,
  venue_lng double precision,
  checked_in_at timestamptz
)
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := auth.uid();
  v_sharing boolean;
begin
  if v_me is null then return; end if;

  select p.share_location_with_friends into v_sharing
    from public.profiles p where p.id = v_me;
  if not coalesce(v_sharing, false) then
    return;   -- (c) reciprocity
  end if;

  return query
  select
    friend.id,
    friend.display_name,
    friend.avatar_url,
    friend.avatar_config,
    v.id,
    v.name,
    v.lat,
    v.lng,
    c.checked_in_at
  from public.friendships f
  join public.profiles friend
    on friend.id = case when f.user_a = v_me then f.user_b else f.user_a end
  join public.venue_checkins c on c.user_id = friend.id and c.checked_out_at is null
  join public.venues v on v.id = c.venue_id
  where f.status = 'accepted'
    and (f.user_a = v_me or f.user_b = v_me)
    and friend.share_location_with_friends
    and not public.bp_blocked_between(v_me, friend.id)
    -- A night is at most 24h; this bound keeps the scan small before the
    -- exact per-venue-timezone night test below.
    and c.checked_in_at > now() - interval '30 hours'
    and public.bp_night_end(public.bp_night_of(c.checked_in_at, v.timezone), v.timezone) > now()
  order by c.checked_in_at desc;
end;
$$;

-- Re-grant EXECUTE on the four functions. The DROP above wiped the grants
-- that friend_graph_schema.sql section 9 installed; without these, the
-- iOS client's /rest/v1/rpc/list_friends and the other three will return
-- 42501 permission denied and the Friends tab goes dead.
grant execute on function public.list_friends()                       to authenticated;
grant execute on function public.search_profiles(text)                to authenticated;
grant execute on function public.redeem_friend_code(text)             to authenticated;
grant execute on function public.get_friends_out_tonight()            to authenticated;

-- Defense in depth: friend_graph_schema.sql section 9 revokes execute
-- from `public` and `anon` on these four. The REVOKE from PUBLIC survived
-- the DROP+CREATE (PUBLIC is a built-in role, not a grant on a specific
-- name), but re-asserting both is cheap.
revoke execute on function public.list_friends()                      from public, anon;
revoke execute on function public.search_profiles(text)               from public, anon;
revoke execute on function public.redeem_friend_code(text)            from public, anon;
revoke execute on function public.get_friends_out_tonight()           from public, anon;

-- PostgREST caches function schemas; nudge the cache so clients see the
-- new avatar_config column without waiting for the auto-reload.
notify pgrst, 'reload schema';

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════
--
-- 1. Column added, correct type and nullable.
--    select column_name, data_type, is_nullable
--      from information_schema.columns
--     where table_schema = 'public' and table_name = 'profiles' and column_name = 'avatar_config';
--    -- expect: avatar_config | jsonb | YES
--
-- 2. Size/shape constraint is in place.
--    select conname, pg_get_constraintdef(oid) from pg_constraint
--     where conname = 'profiles_avatar_config_object';
--    -- expect: one row, definition mentions pg_column_size < 2048
--
-- 3. All four functions now return avatar_config jsonb in the right position.
--    select proname, pg_get_function_result(oid) as return_type from pg_proc
--     where proname in ('list_friends','search_profiles','redeem_friend_code','get_friends_out_tonight')
--       and pronamespace = 'public'::regnamespace
--     order by proname;
--    -- expect: each TABLE(...) definition contains 'avatar_config jsonb'
--
-- 4. EXECUTE grants survived. If anon shows up here the migration also
--    undid friend_graph_schema.sql section 9's revoke — a security regression.
--    select p.proname,
--           has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_exec,
--           has_function_privilege('anon', p.oid, 'EXECUTE')         as anon_exec
--      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--     where n.nspname = 'public'
--       and p.proname in ('list_friends','search_profiles','redeem_friend_code','get_friends_out_tonight');
--    -- expect: auth_exec = true, anon_exec = false for all four
--
-- 5. search_path still pinned to just 'public' (no accidental extensions drift).
--    select p.proname, p.proconfig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--     where n.nspname = 'public'
--       and p.proname in ('list_friends','search_profiles','redeem_friend_code','get_friends_out_tonight');
--    -- expect: proconfig = {search_path=public} for each
--
-- 6. End-to-end: as a signed-in test user (via supabase.auth, not SQL editor),
--    write and read back avatar_config.
--    update public.profiles
--       set avatar_config = jsonb_build_object(
--             'skin_tone','tan','hair_style','short','hair_color','black',
--             'accessory','sunglasses','outfit_color','amber','expression','smile')
--     where id = auth.uid();
--    select avatar_config from public.profiles where id = auth.uid();
--
-- 7. list_friends() returns avatar_config populated when the friend has one.
--    select * from public.list_friends();
