-- Chapter-created events — a chapter's own members organizing something
-- (a mixer, a date party, a study night) without needing a commercial
-- venue partnership first. Deliberately a separate table from `events`
-- (which is always venue_id-anchored, real cover pricing, student pricing,
-- the whole commercial ticketing path) — a chapter mixer at someone's house
-- isn't a venue event and forcing it into that table would mean either a
-- fake venue_id or loosening venue_id's NOT NULL for everyone.
--
-- Same security shape as chapter_chat.sql throughout: affiliation + ban
-- checked server-side inside SECURITY DEFINER RPCs, never trusted from the
-- client; RLS on the tables as the second layer, not the only one.
--
-- Idempotent, safe to re-run.

create table if not exists public.chapter_events (
  id uuid primary key default gen_random_uuid(),
  chapter_id uuid references public.greek_chapters(id) not null,
  created_by uuid references public.profiles(id) not null,
  title text not null check (char_length(title) between 1 and 120),
  description text check (description is null or char_length(description) <= 1000),
  location_name text check (location_name is null or char_length(location_name) <= 200),
  starts_at timestamptz not null,
  ends_at timestamptz,
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  deleted_by uuid references public.profiles(id)
);

create table if not exists public.chapter_event_rsvps (
  event_id uuid references public.chapter_events(id) on delete cascade not null,
  user_id uuid references public.profiles(id) not null,
  created_at timestamptz not null default now(),
  primary key (event_id, user_id)
);

alter table public.chapter_events enable row level security;
alter table public.chapter_event_rsvps enable row level security;

drop policy if exists "view chapter events" on public.chapter_events;
create policy "view chapter events" on public.chapter_events for select
  to authenticated
  using (
    chapter_id = (select chapter_id from public.profiles where id = auth.uid())
    and deleted_at is null
    and not exists (
      select 1 from public.chapter_bans
      where chapter_id = chapter_events.chapter_id and user_id = auth.uid()
        and (expires_at is null or expires_at > now())
    )
  );

-- RSVP rows are only meaningful in the context of an event the viewer can
-- already see — reuse that same gate via a join instead of duplicating the
-- affiliation/ban logic a second time.
drop policy if exists "view chapter event rsvps" on public.chapter_event_rsvps;
create policy "view chapter event rsvps" on public.chapter_event_rsvps for select
  to authenticated
  using (
    exists (
      select 1 from public.chapter_events e
      where e.id = chapter_event_rsvps.event_id
        and e.chapter_id = (select chapter_id from public.profiles where id = auth.uid())
        and e.deleted_at is null
    )
  );

create or replace function public.create_chapter_event(
  p_title text, p_starts_at timestamptz,
  p_description text default null, p_location_name text default null,
  p_ends_at timestamptz default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_chapter_id uuid;
  v_recent_count int;
  v_event_id uuid;
begin
  if char_length(trim(p_title)) = 0 or char_length(p_title) > 120 then
    raise exception 'title must be 1-120 characters';
  end if;
  if p_starts_at < now() - interval '1 hour' then
    raise exception 'event cannot start in the past';
  end if;
  if p_starts_at > now() + interval '1 year' then
    raise exception 'event is too far in the future';
  end if;
  if p_ends_at is not null and p_ends_at < p_starts_at then
    raise exception 'end time cannot be before start time';
  end if;

  select chapter_id into v_chapter_id from profiles where id = auth.uid();
  if v_chapter_id is null then
    raise exception 'no chapter affiliation set';
  end if;
  if exists (
    select 1 from chapter_bans
    where chapter_id = v_chapter_id and user_id = auth.uid()
      and (expires_at is null or expires_at > now())
  ) then
    raise exception 'banned from this chapter';
  end if;

  -- Generous but real cap — this is spam/abuse prevention, not a product
  -- limit; a chapter running a normal event calendar never gets close.
  select count(*) into v_recent_count from chapter_events
    where created_by = auth.uid() and created_at > now() - interval '24 hours';
  if v_recent_count >= 5 then
    raise exception 'rate limit exceeded';
  end if;

  insert into chapter_events (chapter_id, created_by, title, description, location_name, starts_at, ends_at)
    values (v_chapter_id, auth.uid(), trim(p_title), nullif(trim(coalesce(p_description, '')), ''),
            nullif(trim(coalesce(p_location_name, '')), ''), p_starts_at, p_ends_at)
    returning id into v_event_id;
  return v_event_id;
end;
$$;

-- Only the creator can take their own event down — no chapter-officer
-- concept exists yet (affiliation is self-declared, not a verified role),
-- so this deliberately doesn't try to fake one.
create or replace function public.delete_chapter_event(p_event_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update chapter_events
    set deleted_at = now(), deleted_by = auth.uid()
    where id = p_event_id and created_by = auth.uid() and deleted_at is null;
end;
$$;

-- Toggles the caller's own RSVP and returns the event's fresh state in one
-- round trip (no separate count query the client has to reconcile).
create or replace function public.toggle_chapter_event_rsvp(p_event_id uuid)
returns table (going boolean, rsvp_count int)
language plpgsql security definer set search_path = public as $$
declare
  v_chapter_id uuid;
  v_event_chapter_id uuid;
begin
  select chapter_id into v_chapter_id from profiles where id = auth.uid();
  select chapter_id into v_event_chapter_id from chapter_events where id = p_event_id and deleted_at is null;
  if v_chapter_id is null or v_event_chapter_id is null or v_chapter_id != v_event_chapter_id then
    raise exception 'not a member of this event''s chapter';
  end if;
  if exists (
    select 1 from chapter_bans
    where chapter_id = v_chapter_id and user_id = auth.uid()
      and (expires_at is null or expires_at > now())
  ) then
    raise exception 'banned from this chapter';
  end if;

  if exists (select 1 from chapter_event_rsvps where event_id = p_event_id and user_id = auth.uid()) then
    delete from chapter_event_rsvps where event_id = p_event_id and user_id = auth.uid();
  else
    insert into chapter_event_rsvps (event_id, user_id) values (p_event_id, auth.uid());
  end if;

  return query
    select
      exists (select 1 from chapter_event_rsvps where event_id = p_event_id and user_id = auth.uid()),
      (select count(*)::int from chapter_event_rsvps where event_id = p_event_id);
end;
$$;

-- One round trip for the list screen: events + rsvp_count + whether the
-- caller is going, upcoming-first, already scoped to the caller's chapter
-- server-side (chapter_id is never a client-supplied filter here).
create or replace function public.list_chapter_events()
returns table (
  id uuid, title text, description text, location_name text,
  starts_at timestamptz, ends_at timestamptz, created_by uuid,
  created_at timestamptz, rsvp_count int, going boolean
)
language plpgsql security definer set search_path = public as $$
declare
  v_chapter_id uuid;
begin
  select chapter_id into v_chapter_id from profiles where id = auth.uid();
  if v_chapter_id is null then
    return;
  end if;
  if exists (
    select 1 from chapter_bans
    where chapter_id = v_chapter_id and user_id = auth.uid()
      and (expires_at is null or expires_at > now())
  ) then
    return;
  end if;

  return query
    select e.id, e.title, e.description, e.location_name, e.starts_at, e.ends_at, e.created_by, e.created_at,
           (select count(*)::int from chapter_event_rsvps r where r.event_id = e.id),
           exists (select 1 from chapter_event_rsvps r where r.event_id = e.id and r.user_id = auth.uid())
    from chapter_events e
    where e.chapter_id = v_chapter_id and e.deleted_at is null
    order by e.starts_at asc;
end;
$$;

revoke execute on function public.create_chapter_event(text, timestamptz, text, text, timestamptz) from public, anon;
grant execute on function public.create_chapter_event(text, timestamptz, text, text, timestamptz) to authenticated;
revoke execute on function public.delete_chapter_event(uuid) from public, anon;
grant execute on function public.delete_chapter_event(uuid) to authenticated;
revoke execute on function public.toggle_chapter_event_rsvp(uuid) from public, anon;
grant execute on function public.toggle_chapter_event_rsvp(uuid) to authenticated;
revoke execute on function public.list_chapter_events() from public, anon;
grant execute on function public.list_chapter_events() to authenticated;

create index if not exists chapter_events_chapter_idx on public.chapter_events (chapter_id, starts_at);
create index if not exists chapter_event_rsvps_event_idx on public.chapter_event_rsvps (event_id);
