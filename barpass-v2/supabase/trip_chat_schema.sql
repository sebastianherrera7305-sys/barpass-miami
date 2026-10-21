-- TRIP CHAT — the one missing primitive behind GroupNightView's "Chat del
-- grupo". The view already asks for messages against this table through
-- `TripChatRepository`; until this migration runs, every call returns an
-- empty list and the card silently empty-states (that is deliberate: an
-- honest empty beats a fake "próximamente" placeholder).
--
-- Idempotent, safe to re-run. Run AFTER: trips_schema.sql (for the
-- trips.member_ids / creator_id columns this RLS predicate reads).
--
--
-- WHY A SEPARATE TABLE
-- ------------------------------------------------------------------
-- A trip is not a Greek chapter and is not a 1:1 friendship, so this
-- can't reuse chapter_messages (scoped to a chapter affiliation) or
-- friend_messages (encrypted 1:1 with a hard rate limit). Trips have a
-- tiny roster (3-10 people), ephemeral membership, and a known
-- authorisation source already in Postgres: `trips.member_ids` plus
-- `trips.creator_id`. One table, one RLS predicate against that source,
-- no sync problem.
--
--
-- PLAIN TEXT, NOT ENCRYPTED
-- ------------------------------------------------------------------
-- The friend_chat tables encrypt message bodies with a key held in
-- Supabase Vault — the right call for a 1:1 DM where the two sides may
-- fall out and one wants to report the other. A trip chat is a group of
-- consenting co-planners who already share every other datum of the
-- night (invite code, itinerary, "who's going"). Encrypting the body
-- here would add complexity (vault keys, SECURITY DEFINER decrypt RPCs,
-- cipher rotations) with no privacy win the RLS boundary isn't already
-- enforcing. Mirrors chapter_chat.sql's choice for the same reason.

create extension if not exists pgcrypto;

-- ==================================================================
-- 1. TABLE
-- ==================================================================

create table if not exists public.trip_messages (
    id         uuid        primary key default gen_random_uuid(),
    trip_id    uuid        not null references public.trips(id) on delete cascade,
    user_id    uuid        not null references auth.users(id)   on delete cascade,
    text       text        not null check (char_length(text) between 1 and 1000),
    created_at timestamptz not null default now()
);

-- The one query shape anyone runs: "give me this trip's messages, newest
-- last (or everything newer than when I last polled)". A compound index
-- on (trip_id, created_at) answers both — the planner reads it as a seek
-- + range scan either way.
create index if not exists trip_messages_trip_time_idx
    on public.trip_messages (trip_id, created_at);


-- ==================================================================
-- 2. RLS — the trip membership IS the ACL
-- ==================================================================
--
-- SELECT allowed when auth.uid() is in (creator_id, member_ids) of the
-- referenced trip; INSERT allowed when same AND user_id = auth.uid().
-- No one ever updates or deletes a message (there is no "edit" affordance
-- in the client), so no update/delete policy.

alter table public.trip_messages enable row level security;

drop policy if exists trip_messages_select on public.trip_messages;
create policy trip_messages_select on public.trip_messages
    for select
    to authenticated
    using (
        exists (
            select 1 from public.trips t
            where t.id = trip_messages.trip_id
              and (auth.uid() = t.creator_id or auth.uid() = any(t.member_ids))
        )
    );

drop policy if exists trip_messages_insert on public.trip_messages;
create policy trip_messages_insert on public.trip_messages
    for insert
    to authenticated
    with check (
        user_id = auth.uid()
        and exists (
            select 1 from public.trips t
            where t.id = trip_messages.trip_id
              and (auth.uid() = t.creator_id or auth.uid() = any(t.member_ids))
        )
    );


-- ==================================================================
-- 3. READ RPC — join with display name
-- ==================================================================
--
-- `public.profiles` is readable only by its owner (schema.sql: "read own
-- profile"), so a plain PostgREST join on trip_messages → profiles would
-- hide every row's sender name from everyone except themselves. This
-- RPC runs SECURITY DEFINER to resolve display names for the roster of
-- the requested trip — and only that trip, re-checking membership on
-- every call so a user who was removed between calls stops seeing names
-- (and messages) immediately.
--
-- `p_since` is optional: pass the timestamp of your last-seen message to
-- poll for the delta; pass null (default) for the full backlog.

create or replace function public.get_trip_messages(
    p_trip_id uuid,
    p_since   timestamptz default null
)
returns table (
    id           uuid,
    trip_id      uuid,
    user_id      uuid,
    display_name text,
    text         text,
    created_at   timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
    -- Re-check membership here, not only in RLS: this function runs as
    -- the owner, so without this guard the SELECT below would bypass the
    -- row-level policy entirely.
    if not exists (
        select 1 from public.trips t
        where t.id = p_trip_id
          and (auth.uid() = t.creator_id or auth.uid() = any(t.member_ids))
    ) then
        -- Return zero rows rather than raising: matches friend_graph_schema
        -- semantics (a removed/blocked user polls into silence instead of a
        -- distinguishable error).
        return;
    end if;

    return query
        select m.id,
               m.trip_id,
               m.user_id,
               p.display_name,
               m.text,
               m.created_at
        from public.trip_messages m
        left join public.profiles p on p.id = m.user_id
        where m.trip_id = p_trip_id
          and (p_since is null or m.created_at > p_since)
        order by m.created_at asc;
end;
$$;

revoke execute on function public.get_trip_messages(uuid, timestamptz) from public, anon;
grant  execute on function public.get_trip_messages(uuid, timestamptz) to authenticated;


-- ==================================================================
-- 4. WRITE RPC — one place to enforce rate/size, returns the row
-- ==================================================================
--
-- The client could insert through PostgREST directly (the insert policy
-- above would allow it), but routing through an RPC keeps rate limiting
-- and the "return the stored row with display_name" shape in one place.
-- Modelled on send_chapter_message.

create or replace function public.send_trip_message(
    p_trip_id uuid,
    p_text    text
)
returns table (
    id           uuid,
    trip_id      uuid,
    user_id      uuid,
    display_name text,
    text         text,
    created_at   timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
    v_recent_count int;
    v_message_id   uuid;
begin
    if not exists (
        select 1 from public.trips t
        where t.id = p_trip_id
          and (auth.uid() = t.creator_id or auth.uid() = any(t.member_ids))
    ) then
        raise exception 'not_a_member';
    end if;

    if p_text is null or char_length(trim(p_text)) = 0 then
        raise exception 'empty_message';
    end if;

    if char_length(p_text) > 1000 then
        raise exception 'message_too_long';
    end if;

    -- Same cadence as chapter chat: 10 msgs / 5 minutes per sender.
    -- Caught by the client-side disabled state too, but the server is
    -- the only enforcement that matters.
    select count(*) into v_recent_count
    from public.trip_messages
    where user_id = auth.uid()
      and trip_id = p_trip_id
      and created_at > now() - interval '5 minutes';
    if v_recent_count >= 10 then
        raise exception 'rate_limit_exceeded';
    end if;

    insert into public.trip_messages (trip_id, user_id, text)
    values (p_trip_id, auth.uid(), p_text)
    returning trip_messages.id into v_message_id;

    return query
        select m.id,
               m.trip_id,
               m.user_id,
               p.display_name,
               m.text,
               m.created_at
        from public.trip_messages m
        left join public.profiles p on p.id = m.user_id
        where m.id = v_message_id;
end;
$$;

revoke execute on function public.send_trip_message(uuid, text) from public, anon;
grant  execute on function public.send_trip_message(uuid, text) to authenticated;
