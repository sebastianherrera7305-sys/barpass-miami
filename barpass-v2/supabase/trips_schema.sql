-- Trips backend: turns Trips from a per-device local JSON file into a real
-- shared table so members on different phones can see/join the same trip.
-- Run this once in the Supabase SQL editor.
--
-- Stops are kept as an embedded jsonb array (not a separate table) to match
-- the existing Swift `Trip.stops: [Stop]` model 1:1 — no join needed for v1.

create table if not exists public.trips (
    id                 uuid primary key default gen_random_uuid(),
    creator_id         uuid not null references auth.users(id) on delete cascade,
    title              text not null,
    destination_city   text not null,
    start_date         timestamptz not null,
    end_date           timestamptz not null,
    cover_image        text,
    visibility         text not null default 'private' check (visibility in ('private', 'semi_open', 'public')),
    status             text not null default 'planning' check (status in ('planning', 'active', 'completed')),
    member_ids         uuid[] not null default '{}',
    co_organizer_ids   uuid[] not null default '{}',
    pending_requests   uuid[] not null default '{}',
    invite_code        text unique,
    stops              jsonb not null default '[]',
    created_at         timestamptz not null default now(),
    updated_at         timestamptz not null default now()
);

create index if not exists trips_creator_id_idx on public.trips (creator_id);
create index if not exists trips_member_ids_idx on public.trips using gin (member_ids);
create index if not exists trips_invite_code_idx on public.trips (invite_code);

create or replace function public.trips_set_updated_at()
returns trigger language plpgsql as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

drop trigger if exists trips_updated_at on public.trips;
create trigger trips_updated_at
    before update on public.trips
    for each row execute function public.trips_set_updated_at();

alter table public.trips enable row level security;

-- Read: creator, any member, or anyone (for public/semi-open trips so they
-- can be discovered and joined before becoming a member).
drop policy if exists trips_select on public.trips;
create policy trips_select on public.trips
    for select using (
        auth.uid() = creator_id
        or auth.uid() = any(member_ids)
        or visibility <> 'private'
    );

-- Insert: you can only create a trip as yourself.
drop policy if exists trips_insert on public.trips;
create policy trips_insert on public.trips
    for insert with check (auth.uid() = creator_id);

-- Update: creator or any current member. The client always PATCHes the full
-- row (joins, role changes, stop edits all go through the same path) — this
-- matches the app's existing trust model (see LocalTripRepository before
-- this migration), it is NOT a fully tamper-proof per-field ACL. A member
-- could in principle overwrite fields they shouldn't; tightening this to
-- per-field policies is a reasonable follow-up once real abuse shows up.
drop policy if exists trips_update on public.trips;
create policy trips_update on public.trips
    for update using (
        auth.uid() = creator_id
        or auth.uid() = any(member_ids)
    );

-- Delete: creator only.
drop policy if exists trips_delete on public.trips;
create policy trips_delete on public.trips
    for delete using (auth.uid() = creator_id);

-- Joining by invite code can't be a plain client-side SELECT filter: RLS
-- can't see "the code the client is filtering by" when deciding row
-- visibility, so a naive `?invite_code=eq.XXXX` policy would either block
-- legitimate joins to private trips, or (if loosened to "visible whenever
-- invite_code is set") let anyone list every private trip that ever
-- generated a code by just querying without a filter. This RPC runs with
-- elevated privileges to do the lookup+join atomically server-side instead,
-- so the client never sees rows it doesn't already have access to.
create or replace function public.redeem_trip_invite(p_code text)
returns public.trips
language plpgsql
security definer
set search_path = public
as $$
declare
    v_trip public.trips;
begin
    select * into v_trip from public.trips where invite_code = upper(p_code);
    if not found then
        raise exception 'invite_not_found';
    end if;

    if not (auth.uid() = any(v_trip.member_ids) or auth.uid() = v_trip.creator_id) then
        update public.trips
        set member_ids = array_append(member_ids, auth.uid())
        where id = v_trip.id
        returning * into v_trip;
    end if;

    return v_trip;
end;
$$;

grant execute on function public.redeem_trip_invite(text) to authenticated;
