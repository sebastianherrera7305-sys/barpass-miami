-- ─────────────────────────────────────────────────────────────────────────
-- BarPass V2 — WHO IS HOSTING: a promoter, or the club itself.
--
-- Run in the Supabase SQL editor. Idempotent — safe to re-run.
--
-- host_events originally carried only `host_id` (a user), which treats a
-- promoter throwing a party AT a club and the club running ITS OWN night as
-- the same thing. They are not, and the difference is visible to the person
-- reading the flyer: "Tuesday Night at MacDinton's" put up by MacDinton's is
-- the venue's own night; the identical event put up by a promoter is someone
-- renting the room. It also decides who gets credited, and later, who gets paid.
--
-- `venue_owners` already exists (venue_owner_events_promos.sql) and is the
-- authority on "does this user speak for this venue". It is deliberately
-- provisioned by ops with the service role — there is no self-serve path to
-- claim a venue, and this file does not add one. Anyone can host as a
-- PROMOTER; hosting as the VENUE has to be earned.
-- ─────────────────────────────────────────────────────────────────────────

alter table public.host_events
  add column if not exists host_type text not null default 'promoter';

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'host_events_host_type_check'
  ) then
    alter table public.host_events
      add constraint host_events_host_type_check
      check (host_type in ('promoter', 'venue'));
  end if;
end $$;

-- The display name the flyer shows. For a promoter this is their brand
-- ("Collegiate Nightlife"), which is NOT their personal display name and must
-- not silently become it. NULL means "fall back to the venue's name for a
-- venue-hosted night, or the host's profile name for a promoter".
alter table public.host_events
  add column if not exists host_display_name text
  check (host_display_name is null or char_length(trim(host_display_name)) between 1 and 60);

comment on column public.host_events.host_type is
  'promoter = an individual or brand renting the room; venue = the club running its own night, which requires a venue_owners row for (host_id, venue_id).';

-- Claiming to BE the venue is checked here rather than in route code, because
-- a check that lives in one API handler is a check the next handler forgets.
create or replace function public.enforce_host_type()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.host_type = 'venue' then
    if not exists (
      select 1 from public.venue_owners o
      where o.user_id = new.host_id and o.venue_id = new.venue_id
    ) then
      raise exception 'not_a_venue_owner';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists enforce_host_type_insert on public.host_events;
create trigger enforce_host_type_insert
  before insert on public.host_events
  for each row execute function public.enforce_host_type();

-- Also on UPDATE: without this, anyone could create a promoter event and then
-- edit host_type to 'venue', which is the same class of hole as the trips
-- creator_id takeover.
drop trigger if exists enforce_host_type_update on public.host_events;
create trigger enforce_host_type_update
  before update on public.host_events
  for each row when (new.host_type is distinct from old.host_type
                     or new.venue_id is distinct from old.venue_id)
  execute function public.enforce_host_type();

revoke execute on function public.enforce_host_type() from public, anon, authenticated;

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════
--
-- Column and constraint exist.                     -- expect 1 row, 'promoter'
--   select column_name, column_default from information_schema.columns
--    where table_name = 'host_events' and column_name = 'host_type';
--
-- Nobody is falsely claiming to be a venue.        -- expect 0 rows
--   select e.id, e.title from public.host_events e
--    where e.host_type = 'venue'
--      and not exists (select 1 from public.venue_owners o
--                       where o.user_id = e.host_id and o.venue_id = e.venue_id);
--
-- The trigger actually bites (run as service role; expect not_a_venue_owner):
--   insert into public.host_events (host_id, venue_id, title, starts_at, host_type)
--   select id, (select id from public.venues limit 1), 'ZZ trigger test', now(), 'venue'
--     from auth.users limit 1;
