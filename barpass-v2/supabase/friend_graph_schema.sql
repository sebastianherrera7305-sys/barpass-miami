-- FRIEND GRAPH — the one missing thing behind three of the four gaps the
-- owner listed: "no se puede agregar a gente", "no deja chatear", "en el
-- mapa no aparecen tus amigos". All three need the same primitive: a
-- mutual, consented relationship between two users. This file is that
-- primitive plus everything it unlocks (discovery, 1:1 chat, presence).
--
-- Idempotent, safe to re-run. Run AFTER: schema.sql, the_grid.sql,
-- venue_geography_schema.sql, venue_stories.sql (for bp_night_of /
-- bp_night_end), chapter_chat_encryption.sql (for the pgcrypto/vault
-- pattern this reuses).
--
--
-- SYMMETRIC FRIENDSHIP, NOT ASYMMETRIC FOLLOW — and why
-- ------------------------------------------------------------------
-- A follow graph is the right shape when the payoff is CONTENT: I want
-- your posts, you don't have to want mine. This app's payoff is
-- LOCATION — "see where your friends are tonight" — and location is not
-- content, it is a safety-relevant fact about a person's body.
--
-- Under a follow model, the act of following is unilateral: anyone who
-- finds you can start receiving your whereabouts, and the only defence
-- left is a block AFTER the fact. On a college campus, with a free and
-- instant signup, that is a stalking tool with a map attached. It also
-- breaks the other two features: a DM inbox open to anyone who followed
-- you is a spam inbox, and "add a friend" stops being a decision the
-- other person gets to make.
--
-- Mutual accept makes consent the precondition rather than the cleanup.
-- It gives one unambiguous answer to every downstream question — can I
-- see their check-in, can I DM them, do they appear on my map — instead
-- of three separate permission systems. The cost is one extra tap by the
-- recipient, which is exactly the tap that makes the rest defensible.
--
--
-- ONE ROW PER PAIR
-- ------------------------------------------------------------------
-- The classic bug in friendship tables is two rows per relationship
-- (A→B and B→A) drifting out of sync: A→B accepted while B→A is still
-- pending, so "are we friends" depends on which row you happen to read.
-- Here the pair is canonicalised — user_a is always the lexically
-- smaller uuid — and (user_a, user_b) is the primary key, so the
-- relationship physically cannot exist twice. Direction is not lost:
-- `requested_by` says who asked, which is all a pending request needs.

create extension if not exists pgcrypto;
create extension if not exists supabase_vault cascade;


-- ==================================================================
-- 1. PROFILE COLUMNS
-- ==================================================================

-- Opt-in, per user, and OFF by default. A user who never opens the
-- friends screen never broadcasts a check-in to anybody. (See section 7
-- for the full privacy model.)
alter table public.profiles
  add column if not exists share_location_with_friends boolean not null default false;

-- Lets a user disappear from name search without deleting their account
-- or losing their existing friends. Their friend code still works — that
-- is the point of a code: discovery by deliberate sharing, not by being
-- findable.
alter table public.profiles
  add column if not exists friend_discoverable boolean not null default true;

-- Same idea as trips.invite_code: a short, speakable, paste-tolerant
-- string you hand to someone in person or over WhatsApp.
alter table public.profiles
  add column if not exists friend_code text unique;

create index if not exists profiles_friend_code_idx on public.profiles (friend_code);

-- Name search is an ILIKE '%q%'; a trigram GIN index is what keeps that
-- from being a seq scan over every profile on every keystroke.
--
-- Wrapped in a DO/EXCEPTION because on a hosted Supabase project pg_trgm
-- lives in the `extensions` schema, and whether `gin_trgm_ops` resolves
-- depends on the session search_path. The index is a pure optimisation —
-- search works without it at 11 profiles and at 11,000 — so a failure to
-- create it must NOT abort the rest of this migration. Both spellings are
-- tried; if neither takes, the script says so and carries on.
do $$
begin
  create extension if not exists pg_trgm;
exception when others then
  raise notice 'pg_trgm not available (%), name search will use a seq scan', sqlerrm;
end $$;

do $$
begin
  create index if not exists profiles_display_name_trgm_idx
    on public.profiles using gin (display_name gin_trgm_ops);
exception when others then
  begin
    execute 'create index if not exists profiles_display_name_trgm_idx
               on public.profiles using gin (display_name extensions.gin_trgm_ops)';
  exception when others then
    raise notice 'skipping trigram index on profiles.display_name: %', sqlerrm;
  end;
end $$;

-- profiles' "update own profile" policy is row-level: an owner may PATCH
-- any column of their own row, including one they should not choose for
-- themselves. friend_code is issued by get_or_create_friend_code() and
-- must stay server-assigned — otherwise a user could squat a short code
-- they expect someone else to be given, or rotate codes to dodge a
-- block. Same trigger pattern as protect_profile_points() in schema.sql:
-- a client update silently keeps the old value. NULL → non-NULL is
-- allowed only for the SECURITY DEFINER path, which sets it while
-- auth.uid() is still the owner, so the guard tests "was already set".
create or replace function public.protect_profile_friend_code()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.friend_code is not null and new.friend_code is distinct from old.friend_code then
    new.friend_code := old.friend_code;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_protect_profile_friend_code on public.profiles;
create trigger trg_protect_profile_friend_code
  before update on public.profiles
  for each row execute function public.protect_profile_friend_code();


-- ==================================================================
-- 2. TABLES
-- ==================================================================

create table if not exists public.friendships (
  user_a uuid not null references public.profiles(id) on delete cascade,
  user_b uuid not null references public.profiles(id) on delete cascade,
  requested_by uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  primary key (user_a, user_b),
  constraint friendships_canonical_order check (user_a < user_b),
  constraint friendships_requester_is_member check (requested_by in (user_a, user_b))
);

create index if not exists friendships_user_b_idx on public.friendships (user_b);
create index if not exists friendships_status_idx on public.friendships (status);

-- Blocks are inherently one-directional as an ACT (I blocked you) and
-- bidirectional in EFFECT (neither of us can reach the other). The row
-- records the act; bp_blocked_between() below reads it in both
-- directions so the effect is symmetric everywhere it is checked.
create table if not exists public.user_blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint user_blocks_not_self check (blocker_id <> blocked_id)
);

create index if not exists user_blocks_blocked_idx on public.user_blocks (blocked_id);

-- One thread per canonical pair, created lazily on the first message.
create table if not exists public.friend_threads (
  id uuid primary key default gen_random_uuid(),
  user_a uuid not null references public.profiles(id) on delete cascade,
  user_b uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  last_message_at timestamptz,
  unique (user_a, user_b),
  constraint friend_threads_canonical_order check (user_a < user_b)
);

-- Same encryption-at-rest posture as chapter_messages: `text` stays NULL,
-- content lives in text_enc, and only the SECURITY DEFINER RPCs hold the
-- vault key. A DB dump or a leaked service-role key does not hand over
-- DM content in plaintext. This is NOT end-to-end — moderation (report
-- + archive) needs server-side inspection — and that tradeoff is the
-- same one chapter_chat_encryption.sql already documents.
create table if not exists public.friend_messages (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references public.friend_threads(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  text_enc bytea not null,
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  report_count int not null default 0
);

create index if not exists friend_messages_thread_idx
  on public.friend_messages (thread_id, created_at desc);
create index if not exists friend_messages_sender_rate_idx
  on public.friend_messages (sender_id, created_at desc);

create table if not exists public.friend_message_reports (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.friend_messages(id) on delete cascade,
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  reason text not null,
  created_at timestamptz not null default now(),
  unique (message_id, reporter_id)
);

create table if not exists public.friend_messages_archive (
  id uuid primary key default gen_random_uuid(),
  original_message_id uuid not null,
  thread_id uuid,
  sender_id uuid,
  text_enc bytea,
  created_at timestamptz,
  deleted_at timestamptz,
  report_count int,
  archived_at timestamptz not null default now(),
  archive_reason text
);

create table if not exists public.friend_thread_reads (
  thread_id uuid not null references public.friend_threads(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  last_read_at timestamptz not null default now(),
  primary key (thread_id, user_id)
);

do $$
begin
  if not exists (select 1 from vault.secrets where name = 'friend_chat_key') then
    perform vault.create_secret(encode(gen_random_bytes(32), 'base64'), 'friend_chat_key');
  end if;
end $$;


-- ==================================================================
-- 3. GRANTS AND RLS
-- ==================================================================
--
-- Every table here is revoked at the TABLE level first, then granted
-- back only what a client legitimately needs. A column-level REVOKE is a
-- silent no-op while a table-level GRANT SELECT stands — Postgres checks
-- the table grant and never consults the column list — which is the bug
-- that left venue_media.user_id readable for weeks. Revoke, then grant.
--
-- `authenticated` is NOT an authorization boundary in this app: signup is
-- free and instant, so "any signed-in user" is "anyone". Every policy
-- below is scoped to auth.uid() membership in the row, never to the role.

revoke all on public.friendships            from anon, authenticated;
revoke all on public.user_blocks            from anon, authenticated;
revoke all on public.friend_threads         from anon, authenticated;
revoke all on public.friend_messages        from anon, authenticated;
revoke all on public.friend_message_reports from anon, authenticated;
revoke all on public.friend_messages_archive from anon, authenticated;
revoke all on public.friend_thread_reads    from anon, authenticated;

alter table public.friendships             enable row level security;
alter table public.user_blocks             enable row level security;
alter table public.friend_threads          enable row level security;
alter table public.friend_messages         enable row level security;
alter table public.friend_message_reports  enable row level security;
alter table public.friend_messages_archive enable row level security;
alter table public.friend_thread_reads     enable row level security;

-- The graph is readable ONLY by the two people in it. There is no
-- "friends of friends" read, no public follower count, nothing that lets
-- anyone enumerate another person's social graph.
grant select on public.friendships to authenticated;
drop policy if exists friendships_select_own on public.friendships;
create policy friendships_select_own on public.friendships
  for select to authenticated
  using (auth.uid() = user_a or auth.uid() = user_b);
-- No insert/update/delete policy at all: every mutation goes through the
-- RPCs in section 4, which enforce blocks, self-friending and canonical
-- ordering. A client that could INSERT directly could add itself to
-- someone else's graph without their accept.

grant select on public.user_blocks to authenticated;
drop policy if exists user_blocks_select_own on public.user_blocks;
create policy user_blocks_select_own on public.user_blocks
  for select to authenticated
  using (auth.uid() = blocker_id);
-- Deliberately NOT `or auth.uid() = blocked_id`: a blocked user must not
-- be able to detect that they were blocked. Writes go through
-- block_user()/unblock_user().

-- Threads, messages, reports, reads and the moderation archive have no
-- client grants and no policies at all. Reads go through the decrypting
-- RPCs (the raw rows are opaque bytea anyway); writes go through RPCs
-- that check friendship and blocks. The archive is service-role only,
-- same convention as chapter_messages_archive.


-- ==================================================================
-- 4. HELPERS
-- ==================================================================

-- THE block check. Bidirectional on purpose: it does not matter who
-- blocked whom, a block severs contact both ways. Every RPC that can
-- create contact between two users calls this first.
create or replace function public.bp_blocked_between(p_x uuid, p_y uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.user_blocks b
    where (b.blocker_id = p_x and b.blocked_id = p_y)
       or (b.blocker_id = p_y and b.blocked_id = p_x)
  )
$$;

create or replace function public.bp_are_friends(p_x uuid, p_y uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.friendships f
    where f.user_a = least(p_x, p_y)
      and f.user_b = greatest(p_x, p_y)
      and f.status = 'accepted'
  )
$$;

-- Crockford-ish alphabet: no O/0, no I/1/L. A code read aloud in a loud
-- bar has to survive being misheard, and a code typed back has to
-- survive being mistyped.
create or replace function public.bp_generate_friend_code() returns text
language plpgsql security definer set search_path = public as $$
declare
  v_alphabet text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_code text;
  v_i int;
  v_try int := 0;
begin
  loop
    v_code := '';
    for v_i in 1..6 loop
      v_code := v_code || substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.profiles p where p.friend_code = v_code);
    v_try := v_try + 1;
    if v_try > 20 then
      raise exception 'could not allocate friend code';
    end if;
  end loop;
  return v_code;
end;
$$;


-- ==================================================================
-- 5. GRAPH RPCs
-- ==================================================================

-- Idempotent: hands back the existing code, or mints one on first call.
create or replace function public.get_or_create_friend_code() returns text
language plpgsql security definer set search_path = public as $$
declare
  v_code text;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;
  select p.friend_code into v_code from public.profiles p where p.id = auth.uid();
  if v_code is not null then
    return v_code;
  end if;
  v_code := public.bp_generate_friend_code();
  update public.profiles set friend_code = v_code where id = auth.uid();
  return v_code;
end;
$$;

-- Send (or auto-accept) a friend request.
--
-- Auto-accept is the "they already asked me" case: if B already has a
-- pending request out to A and A now sends one to B, that is two people
-- agreeing, and making A tap Accept on a screen they did not open is
-- pointless friction.
create or replace function public.request_friend(p_user_id uuid) returns text
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := auth.uid();
  v_lo uuid;
  v_hi uuid;
  v_row public.friendships;
  v_recent int;
begin
  if v_me is null then raise exception 'not_authenticated'; end if;
  if p_user_id is null or p_user_id = v_me then raise exception 'invalid_target'; end if;
  if not exists (select 1 from public.profiles p where p.id = p_user_id) then
    raise exception 'user_not_found';
  end if;

  -- A block is checked BEFORE anything is written, and the error is the
  -- same generic one a missing user gets — a blocked user must not be
  -- able to probe "am I blocked" by watching which error comes back.
  if public.bp_blocked_between(v_me, p_user_id) then
    raise exception 'user_not_found';
  end if;

  -- Request spam is the friend-graph equivalent of chat flooding.
  select count(*) into v_recent from public.friendships f
   where f.requested_by = v_me and f.created_at > now() - interval '1 hour';
  if v_recent >= 30 then
    raise exception 'rate_limit_exceeded';
  end if;

  v_lo := least(v_me, p_user_id);
  v_hi := greatest(v_me, p_user_id);

  select * into v_row from public.friendships f where f.user_a = v_lo and f.user_b = v_hi;

  if found then
    if v_row.status = 'accepted' then
      return 'accepted';
    end if;
    if v_row.requested_by = v_me then
      return 'pending';               -- already asked; no-op, not an error
    end if;
    -- They asked first → this is a mutual yes.
    update public.friendships
       set status = 'accepted', responded_at = now()
     where user_a = v_lo and user_b = v_hi;
    return 'accepted';
  end if;

  insert into public.friendships (user_a, user_b, requested_by, status)
  values (v_lo, v_hi, v_me, 'pending');
  return 'pending';
end;
$$;

-- Accept only a request that was sent TO me. `requested_by <> v_me` is
-- load-bearing: without it a requester could accept their own request and
-- friend anyone unilaterally, which would throw away the entire reason
-- this graph is symmetric.
create or replace function public.accept_friend(p_user_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := auth.uid();
  v_lo uuid := least(auth.uid(), p_user_id);
  v_hi uuid := greatest(auth.uid(), p_user_id);
begin
  if v_me is null then raise exception 'not_authenticated'; end if;
  if public.bp_blocked_between(v_me, p_user_id) then raise exception 'user_not_found'; end if;

  update public.friendships f
     set status = 'accepted', responded_at = now()
   where f.user_a = v_lo and f.user_b = v_hi
     and f.status = 'pending'
     and f.requested_by <> v_me;
  if not found then
    raise exception 'no_pending_request';
  end if;
end;
$$;

-- Decline an incoming request, cancel one I sent, or remove an existing
-- friend — all three are "delete the row", and collapsing them into one
-- RPC means there is exactly one code path that can end a relationship.
create or replace function public.remove_friend(p_user_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then raise exception 'not_authenticated'; end if;
  delete from public.friendships f
   where f.user_a = least(v_me, p_user_id)
     and f.user_b = greatest(v_me, p_user_id);
end;
$$;

-- Blocking does four things at once, and all four matter:
--   1. records the block (so contact stays severed in both directions),
--   2. deletes the friendship row (a block must not leave a live edge
--      that some future query forgets to filter),
--   3. soft-deletes the whole message history in that thread, so neither
--      side keeps reading the other's words,
--   4. is idempotent.
-- Chat, presence, search and request all consult bp_blocked_between()
-- independently, so even if a new feature forgets step 2, the block
-- still holds.
create or replace function public.block_user(p_user_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := auth.uid();
  v_thread_id uuid;
begin
  if v_me is null then raise exception 'not_authenticated'; end if;
  if p_user_id is null or p_user_id = v_me then raise exception 'invalid_target'; end if;

  insert into public.user_blocks (blocker_id, blocked_id)
  values (v_me, p_user_id)
  on conflict (blocker_id, blocked_id) do nothing;

  delete from public.friendships f
   where f.user_a = least(v_me, p_user_id)
     and f.user_b = greatest(v_me, p_user_id);

  select t.id into v_thread_id from public.friend_threads t
   where t.user_a = least(v_me, p_user_id) and t.user_b = greatest(v_me, p_user_id);
  if v_thread_id is not null then
    update public.friend_messages m
       set deleted_at = now()
     where m.thread_id = v_thread_id and m.deleted_at is null;
  end if;
end;
$$;

-- Unblocking does NOT restore the friendship or the messages. Getting
-- back in someone's graph after a block should require asking again.
create or replace function public.unblock_user(p_user_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  delete from public.user_blocks b
   where b.blocker_id = auth.uid() and b.blocked_id = p_user_id;
end;
$$;


-- ==================================================================
-- 6. DISCOVERY
-- ==================================================================

-- The friends/requests list. profiles is RLS-scoped to "read own row", so
-- a client cannot join to it for a friend's name — this RPC is the only
-- way to learn a counterparty's display_name, and it only ever returns
-- names of people already in the caller's own graph.
--
-- direction: 'friend' | 'incoming' | 'outgoing'.
create or replace function public.list_friends() returns table (
  user_id uuid,
  display_name text,
  avatar_url text,
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

-- Search by display name.
--
-- Guards, each closing a real enumeration path:
--   - 2-character minimum, so nobody walks the alphabet one letter at a
--     time and dumps the user table.
--   - hard cap of 20 rows.
--   - friend_discoverable = false opts a user out entirely.
--   - a user with no display_name is never returned (nothing to match,
--     and returning bare uuids would be a directory).
--   - blocked people, in either direction, are invisible.
-- No email, no phone, no birthdate, no location is returned or matchable.
create or replace function public.search_profiles(p_query text) returns table (
  user_id uuid,
  display_name text,
  avatar_url text,
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

-- Redeem a friend code. Same shape as redeem_trip_invite(): the lookup
-- cannot be a client-side filter, because RLS cannot see "the code the
-- client is filtering by" and would have to expose either everything or
-- nothing. Whitespace is stripped rather than trimmed — a code pasted
-- from Messages/WhatsApp routinely arrives with a trailing newline, and
-- an exact-match lookup punishing that looks exactly like "no puedo
-- agregar amigos" (the same bug bit trip invites).
--
-- Redeeming sends a request; it does not force a friendship. The code
-- proves you were given it, not that the other person wants you.
create or replace function public.redeem_friend_code(p_code text) returns table (
  user_id uuid,
  display_name text,
  avatar_url text,
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
  select p.id, p.display_name, p.avatar_url,
         case when v_status = 'accepted' then 'friend' else 'outgoing' end
    from public.profiles p where p.id = v_target;
end;
$$;


-- ==================================================================
-- 7. PRESENCE — "who's out tonight"
-- ==================================================================
--
-- PRIVACY MODEL, in full:
--
--  a) venue_checkins keeps its existing posture — owner-read-only RLS, no
--     client write policy. This RPC does not loosen it; it is the single
--     narrow window through which another person's check-in can be seen.
--
--  b) OPT-IN. profiles.share_location_with_friends defaults to FALSE. A
--     user who never touches the toggle is never visible to anyone, even
--     to accepted friends.
--
--  c) RECIPROCAL. You only see friends who share, AND you only see
--     anything at all if you share too. A one-way lurker who watches the
--     whole campus while broadcasting nothing is the exact failure mode a
--     location feature has to design out, and reciprocity is the cheapest
--     honest way to do it. The iOS screen says so explicitly rather than
--     silently returning an empty list.
--
--  d) FRIENDS ONLY, mutual-accepted only. A pending request sees nothing.
--
--  e) BLOCKED IS INVISIBLE, both directions, independently of (d).
--
--  f) VENUE GRANULARITY, NOT COORDINATES. What is returned is the venue
--     the friend checked into, which they chose to announce by tapping
--     "I'm here". No GPS trace, no device location, no history — only the
--     currently-open check-in.
--
--  g) TONIGHT ONLY. The check-in must belong to the night still in
--     progress at that venue's own timezone — the same 6 AM boundary
--     stories use (bp_night_of / bp_night_end from venue_stories.sql), so
--     a 2 AM check-in still counts as Friday night and a 7 AM one does
--     not resurface last night's whereabouts.
--
--  h) NO HISTORY. There is no RPC here that returns where a friend was
--     yesterday. Turning the toggle off makes you vanish immediately;
--     nothing was retained for a friend to page back through.
create or replace function public.get_friends_out_tonight() returns table (
  user_id uuid,
  display_name text,
  avatar_url text,
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

-- The toggle itself. A plain PATCH would also work (it is the caller's
-- own row), but routing it through an RPC keeps the write path shaped
-- like every other privileged write in this schema and gives one place to
-- add an audit trail later.
create or replace function public.set_location_sharing(p_enabled boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  update public.profiles set share_location_with_friends = coalesce(p_enabled, false)
   where id = auth.uid();
end;
$$;

create or replace function public.set_friend_discoverable(p_enabled boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  update public.profiles set friend_discoverable = coalesce(p_enabled, true)
   where id = auth.uid();
end;
$$;


-- ==================================================================
-- 8. 1:1 CHAT
-- ==================================================================
--
-- Same architecture as chapter chat, not a second weaker one: content
-- encrypted at rest with a vault key, reads and writes only through
-- SECURITY DEFINER RPCs, rate limiting and reporting server-side, and a
-- moderation archive that snapshots a message the instant it is hidden.
-- What changes is the membership test — "are these two accepted friends
-- and not blocked" instead of "same chapter and not banned".

create or replace function public.bp_friend_thread(p_other uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := auth.uid();
  v_id uuid;
begin
  if not public.bp_are_friends(v_me, p_other) then
    raise exception 'not_friends';
  end if;
  if public.bp_blocked_between(v_me, p_other) then
    raise exception 'not_friends';
  end if;
  select t.id into v_id from public.friend_threads t
   where t.user_a = least(v_me, p_other) and t.user_b = greatest(v_me, p_other);
  if v_id is null then
    insert into public.friend_threads (user_a, user_b)
    values (least(v_me, p_other), greatest(v_me, p_other))
    on conflict (user_a, user_b) do nothing
    returning id into v_id;
    if v_id is null then
      select t.id into v_id from public.friend_threads t
       where t.user_a = least(v_me, p_other) and t.user_b = greatest(v_me, p_other);
    end if;
  end if;
  return v_id;
end;
$$;

create or replace function public.send_friend_message(p_user_id uuid, p_text text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := auth.uid();
  v_thread_id uuid;
  v_recent int;
  v_key text;
  v_id uuid;
begin
  if v_me is null then raise exception 'not_authenticated'; end if;
  if char_length(coalesce(p_text, '')) = 0 or char_length(p_text) > 1000 then
    raise exception 'message must be 1-1000 characters';
  end if;

  -- Friendship + block are both re-checked here on every single send, not
  -- just when the thread was created. An existing thread must go silent
  -- the moment either side blocks or unfriends.
  v_thread_id := public.bp_friend_thread(p_user_id);

  select count(*) into v_recent from public.friend_messages m
   where m.sender_id = v_me and m.created_at > now() - interval '5 minutes';
  if v_recent >= 30 then
    raise exception 'rate_limit_exceeded';
  end if;

  select decrypted_secret into v_key from vault.decrypted_secrets where name = 'friend_chat_key';
  insert into public.friend_messages (thread_id, sender_id, text_enc)
  values (v_thread_id, v_me, pgp_sym_encrypt(p_text, v_key))
  returning id into v_id;

  update public.friend_threads set last_message_at = now() where id = v_thread_id;
  return v_id;
end;
$$;

-- Every output column is aliased off a subquery (sub.*) and every table
-- reference is qualified. PL/pgSQL turns RETURNS TABLE column names into
-- variables in scope, so a bare `thread_id` or `display_name` here is
-- ambiguous at runtime — the exact bug that broke every chapter-chat load
-- the day get_chapter_messages() shipped.
create or replace function public.get_friend_messages(p_user_id uuid, p_limit int default 200)
returns table (
  id uuid,
  thread_id uuid,
  sender_id uuid,
  text text,
  created_at timestamptz
)
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := auth.uid();
  v_thread_id uuid;
  v_key text;
begin
  if v_me is null then return; end if;
  if not public.bp_are_friends(v_me, p_user_id)
     or public.bp_blocked_between(v_me, p_user_id) then
    return;   -- blocked/unfriended: the thread simply does not exist for you
  end if;

  select t.id into v_thread_id from public.friend_threads t
   where t.user_a = least(v_me, p_user_id) and t.user_b = greatest(v_me, p_user_id);
  if v_thread_id is null then return; end if;

  select decrypted_secret into v_key from vault.decrypted_secrets where name = 'friend_chat_key';

  insert into public.friend_thread_reads (thread_id, user_id, last_read_at)
  values (v_thread_id, v_me, now())
  on conflict (thread_id, user_id) do update set last_read_at = now();

  return query
  select sub.id, sub.thread_id, sub.sender_id, sub.text, sub.created_at
  from (
    select m.id, m.thread_id, m.sender_id,
           pgp_sym_decrypt(m.text_enc, v_key) as text,
           m.created_at
      from public.friend_messages m
     where m.thread_id = v_thread_id and m.deleted_at is null
     order by m.created_at desc
     limit greatest(least(coalesce(p_limit, 200), 500), 1)
  ) sub
  order by sub.created_at asc;
end;
$$;

-- The inbox: one row per thread with a friend, newest first, with an
-- unread flag. Threads with someone who is no longer a friend, or who is
-- blocked, are not listed.
create or replace function public.list_friend_threads() returns table (
  user_id uuid,
  display_name text,
  avatar_url text,
  last_message_at timestamptz,
  has_unread boolean
)
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then return; end if;
  return query
  select sub.user_id, sub.display_name, sub.avatar_url, sub.last_message_at, sub.has_unread
  from (
    select
      other.id as user_id,
      other.display_name as display_name,
      other.avatar_url as avatar_url,
      t.last_message_at as last_message_at,
      (t.last_message_at is not null and t.last_message_at > coalesce(
        (select r.last_read_at from public.friend_thread_reads r
          where r.thread_id = t.id and r.user_id = v_me), 'epoch'::timestamptz)) as has_unread
    from public.friend_threads t
    join public.profiles other
      on other.id = case when t.user_a = v_me then t.user_b else t.user_a end
    where (t.user_a = v_me or t.user_b = v_me)
      and public.bp_are_friends(v_me, other.id)
      and not public.bp_blocked_between(v_me, other.id)
  ) sub
  order by sub.last_message_at desc nulls last;
end;
$$;

-- In a chapter (many participants) auto-hiding took 3 independent
-- reports. A 1:1 thread has exactly one person who can legitimately
-- report — the recipient — so waiting for 3 would mean the feature never
-- fires. One report from the counterparty hides the message immediately;
-- the archive keeps the evidence. A sender cannot report their own
-- message to game this.
create or replace function public.report_friend_message(p_message_id uuid, p_reason text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := auth.uid();
  v_msg public.friend_messages;
  v_thread public.friend_threads;
begin
  if v_me is null then raise exception 'not_authenticated'; end if;
  select * into v_msg from public.friend_messages m where m.id = p_message_id;
  if not found then raise exception 'message_not_found'; end if;
  select * into v_thread from public.friend_threads t where t.id = v_msg.thread_id;
  if v_me not in (v_thread.user_a, v_thread.user_b) then
    raise exception 'message_not_found';
  end if;
  if v_msg.sender_id = v_me then raise exception 'cannot_report_own_message'; end if;

  insert into public.friend_message_reports (message_id, reporter_id, reason)
  values (p_message_id, v_me, coalesce(p_reason, 'unspecified'))
  on conflict (message_id, reporter_id) do nothing;

  update public.friend_messages m
     set report_count = (select count(*) from public.friend_message_reports r
                          where r.message_id = p_message_id),
         deleted_at = coalesce(m.deleted_at, now())
   where m.id = p_message_id;
end;
$$;

create or replace function public.archive_hidden_friend_message() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.deleted_at is not null and old.deleted_at is null then
    insert into public.friend_messages_archive
      (original_message_id, thread_id, sender_id, text_enc, created_at, deleted_at,
       report_count, archive_reason)
    values
      (new.id, new.thread_id, new.sender_id, new.text_enc, new.created_at, new.deleted_at,
       new.report_count,
       case when new.report_count > 0 then 'reported' else 'blocked_or_manual' end);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_archive_hidden_friend_message on public.friend_messages;
create trigger trg_archive_hidden_friend_message
  after update of deleted_at on public.friend_messages
  for each row execute function public.archive_hidden_friend_message();


-- ==================================================================
-- 9. EXECUTE GRANTS
-- ==================================================================
--
-- Revoking from PUBLIC alone does nothing here: Supabase's anon and
-- authenticated roles are granted EXECUTE by name through default
-- privileges, so both must be named explicitly before granting back.
-- Every function below is SECURITY DEFINER; an un-revoked one is an
-- unauthenticated hole straight past RLS.

do $$
declare
  v_sig text;
begin
  foreach v_sig in array array[
    'public.bp_blocked_between(uuid, uuid)',
    'public.bp_are_friends(uuid, uuid)',
    'public.bp_generate_friend_code()',
    'public.bp_friend_thread(uuid)',
    'public.get_or_create_friend_code()',
    'public.request_friend(uuid)',
    'public.accept_friend(uuid)',
    'public.remove_friend(uuid)',
    'public.block_user(uuid)',
    'public.unblock_user(uuid)',
    'public.list_friends()',
    'public.search_profiles(text)',
    'public.redeem_friend_code(text)',
    'public.get_friends_out_tonight()',
    'public.set_location_sharing(boolean)',
    'public.set_friend_discoverable(boolean)',
    'public.send_friend_message(uuid, text)',
    'public.get_friend_messages(uuid, int)',
    'public.list_friend_threads()',
    'public.report_friend_message(uuid, text)'
  ] loop
    execute format('revoke execute on function %s from public, anon, authenticated', v_sig);
  end loop;
end $$;

-- Granted back to `authenticated` only — the ones a signed-in client
-- actually calls. The bp_* helpers, the trigger functions and the code
-- generator stay revoked from every client role: they are internal, and
-- bp_blocked_between()/bp_are_friends() in particular would let a client
-- probe another person's relationships one uuid at a time.
grant execute on function public.get_or_create_friend_code()          to authenticated;
grant execute on function public.request_friend(uuid)                 to authenticated;
grant execute on function public.accept_friend(uuid)                  to authenticated;
grant execute on function public.remove_friend(uuid)                  to authenticated;
grant execute on function public.block_user(uuid)                     to authenticated;
grant execute on function public.unblock_user(uuid)                   to authenticated;
grant execute on function public.list_friends()                       to authenticated;
grant execute on function public.search_profiles(text)                to authenticated;
grant execute on function public.redeem_friend_code(text)             to authenticated;
grant execute on function public.get_friends_out_tonight()            to authenticated;
grant execute on function public.set_location_sharing(boolean)        to authenticated;
grant execute on function public.set_friend_discoverable(boolean)     to authenticated;
grant execute on function public.send_friend_message(uuid, text)      to authenticated;
grant execute on function public.get_friend_messages(uuid, int)       to authenticated;
grant execute on function public.list_friend_threads()                to authenticated;
grant execute on function public.report_friend_message(uuid, text)    to authenticated;


-- ==================================================================
-- 10. VERIFICATION (run by hand after applying; all should hold)
-- ==================================================================
--
-- (a) No client role can read the graph tables at the table level except
--     the two RLS-scoped ones. Expect exactly friendships/user_blocks:
--
--   select table_name, grantee, privilege_type
--     from information_schema.role_table_grants
--    where table_schema = 'public'
--      and table_name in ('friendships','user_blocks','friend_threads',
--                         'friend_messages','friend_message_reports',
--                         'friend_messages_archive','friend_thread_reads')
--      and grantee in ('anon','authenticated')
--    order by table_name, grantee;
--
-- (b) No SECURITY DEFINER function here is executable by anon. Expect 0:
--
--   select p.proname
--     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'public'
--      and (p.proname like 'bp_%friend%' or p.proname like '%friend%'
--           or p.proname in ('block_user','unblock_user','search_profiles'))
--      and has_function_privilege('anon', p.oid, 'EXECUTE');
--
-- (c) Blocking severs contact in BOTH directions. As user A, block B,
--     then as B: search_profiles() must not return A, request_friend(A)
--     must raise user_not_found, get_friend_messages(A) must return 0
--     rows, and send_friend_message(A, 'x') must raise not_friends.
--
-- (d) A one-way friendship cannot exist. The (user_a < user_b) primary
--     key makes it a physical impossibility; confirm with:
--
--   select count(*) from public.friendships where user_a >= user_b;  -- 0
--
-- (e) Presence is reciprocal and opt-in. With sharing OFF,
--     get_friends_out_tonight() returns 0 rows even when friends are
--     checked in and sharing.
