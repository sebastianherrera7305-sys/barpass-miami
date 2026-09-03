-- Campus-wide event discovery. Until now a chapter's events were only ever
-- visible to that chapter's own members (chapter_events.sql) — there was no
-- way for the university as a whole to see "what's happening" across
-- chapters, which is most of the actual social value of a Greek events
-- calendar. Adds an explicit opt-in: a chapter marks an event `is_public`
-- to put it on the university-wide feed; everything else about it (RSVP,
-- edit/delete rights, membership-only chat) is unchanged.
--
-- Run after chapter_events.sql. Idempotent.

alter table public.chapter_events add column if not exists is_public boolean not null default false;

create or replace function public.create_chapter_event(
  p_title text, p_starts_at timestamptz,
  p_description text default null, p_location_name text default null,
  p_ends_at timestamptz default null, p_is_public boolean default false
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

  select count(*) into v_recent_count from chapter_events
    where created_by = auth.uid() and created_at > now() - interval '24 hours';
  if v_recent_count >= 5 then
    raise exception 'rate limit exceeded';
  end if;

  insert into chapter_events (chapter_id, created_by, title, description, location_name, starts_at, ends_at, is_public)
    values (v_chapter_id, auth.uid(), trim(p_title), nullif(trim(coalesce(p_description, '')), ''),
            nullif(trim(coalesce(p_location_name, '')), ''), p_starts_at, p_ends_at, coalesce(p_is_public, false))
    returning id into v_event_id;
  return v_event_id;
end;
$$;

revoke execute on function public.create_chapter_event(text, timestamptz, text, text, timestamptz) from public, anon;
revoke execute on function public.create_chapter_event(text, timestamptz, text, text, timestamptz, boolean) from public, anon;
grant execute on function public.create_chapter_event(text, timestamptz, text, text, timestamptz, boolean) to authenticated;

-- list_chapter_events also needs to hand back is_public now, or the client
-- can't show/toggle it consistently after the fact.
create or replace function public.list_chapter_events()
returns table (
  id uuid, title text, description text, location_name text,
  starts_at timestamptz, ends_at timestamptz, created_by uuid,
  created_at timestamptz, rsvp_count int, going boolean, is_public boolean
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
           exists (select 1 from chapter_event_rsvps r where r.event_id = e.id and r.user_id = auth.uid()),
           e.is_public
    from chapter_events e
    where e.chapter_id = v_chapter_id and e.deleted_at is null
    order by e.starts_at asc;
end;
$$;

-- The campus-wide feed: any authenticated user (not just the organizing
-- chapter's own members — that's the point) can see events chapters at
-- THIS university have explicitly opted to publish. No RSVP/going status
-- here on purpose — RSVPing is a chapter-membership action, kept on the
-- per-chapter screen; this is discovery only.
create or replace function public.list_university_public_events(p_university_id uuid)
returns table (
  id uuid, title text, description text, location_name text,
  starts_at timestamptz, ends_at timestamptz,
  chapter_id uuid, chapter_name text, rsvp_count int
)
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then
    return;
  end if;
  return query
    select e.id, e.title, e.description, e.location_name, e.starts_at, e.ends_at,
           c.id, c.fraternity_name,
           (select count(*)::int from chapter_event_rsvps r where r.event_id = e.id)
    from chapter_events e
    join greek_chapters c on c.id = e.chapter_id
    where c.university_id = p_university_id
      and e.is_public = true
      and e.deleted_at is null
      and e.starts_at >= now() - interval '2 hours'
    order by e.starts_at asc
    limit 50;
end;
$$;

revoke execute on function public.list_university_public_events(uuid) from public, anon;
grant execute on function public.list_university_public_events(uuid) to authenticated;
