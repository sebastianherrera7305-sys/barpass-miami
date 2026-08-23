-- THE GRID — aggregated, anonymous presence per venue. Never exposes a
-- specific user's location: venue_checkins (the raw per-user record) is
-- locked to owner-read-only and written only through check_in_venue()/
-- check_out_venue(); grid_pulses (the public aggregate) is what the app
-- actually displays.
--
-- v1 uses manual check-in (a button on the venue screen), not geofencing —
-- CLLocationManager caps region monitoring at 20 regions per app, which
-- can't cover 176+ venues, and "Always" background location for bar
-- proximity is exactly the kind of thing that draws extra App Store review
-- scrutiny. Geofencing can be revisited later as its own scoped effort.
--
-- Idempotent, safe to re-run.

-- 1. Real birthdate, not just a one-time age-gate tap. Required before
--    check-in; a NULL birthdate simply can't check in yet (non-breaking for
--    existing users).
alter table public.profiles add column if not exists birthdate date;

-- Enforced at the DATA layer, not just in the Swift onboarding UI — a
-- modified client can't bypass this by skipping the app's own validation.
create or replace function public.enforce_adult_birthdate() returns trigger
language plpgsql as $$
begin
  if new.birthdate is not null and new.birthdate > (current_date - interval '18 years')::date then
    raise exception 'must be at least 18 years old';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_adult_birthdate on public.profiles;
create trigger trg_enforce_adult_birthdate
  before insert or update of birthdate on public.profiles
  for each row execute function public.enforce_adult_birthdate();

-- 2. Which venues 18-20 year olds are even allowed to see in Grid/Greek
--    Life contexts. A property of the venue, not sensitive on its own.
alter table public.venues add column if not exists age_policy text not null default '21+'
  check (age_policy in ('18+', '21+', 'mixed'));

-- 3. Raw per-user-per-venue-per-time record — real location history.
--    Locked to owner-read-only; no client insert/update policy at all.
create table if not exists public.venue_checkins (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) not null,
  venue_id uuid references public.venues(id) not null,
  trip_id uuid references public.trips(id),
  chapter_id uuid references public.greek_chapters(id),
  checked_in_at timestamptz not null default now(),
  checked_out_at timestamptz,
  duration_minutes int generated always as (
    extract(epoch from (checked_out_at - checked_in_at)) / 60
  ) stored,
  age_at_checkin int not null
);

alter table public.venue_checkins enable row level security;

drop policy if exists "read own checkins" on public.venue_checkins;
create policy "read own checkins" on public.venue_checkins for select
  to authenticated
  using (user_id = auth.uid());
-- No insert/update/delete policy for anon/authenticated — every write goes
-- through check_in_venue()/check_out_venue() below, which compute
-- age_at_checkin and chapter_id server-side from profiles instead of
-- trusting a client-supplied value (a modified client could otherwise send
-- age_at_checkin=21 for a real 15-year-old).

create or replace function public.check_in_venue(p_venue_id uuid, p_trip_id uuid default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_birthdate date;
  v_age int;
  v_chapter_id uuid;
  v_checkin_id uuid;
begin
  select birthdate, chapter_id into v_birthdate, v_chapter_id from profiles where id = auth.uid();
  if v_birthdate is null then
    raise exception 'birthdate required before check-in';
  end if;
  v_age := extract(year from age(v_birthdate));
  if v_age < 18 then
    raise exception 'must be 18+ to check in';
  end if;
  insert into venue_checkins (user_id, venue_id, trip_id, chapter_id, age_at_checkin)
    values (auth.uid(), p_venue_id, p_trip_id, v_chapter_id, v_age)
    returning id into v_checkin_id;
  return v_checkin_id;
end;
$$;

create or replace function public.check_out_venue(p_checkin_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update venue_checkins set checked_out_at = now()
    where id = p_checkin_id and user_id = auth.uid() and checked_out_at is null;
end;
$$;

revoke execute on function public.check_in_venue(uuid, uuid) from public, anon;
grant execute on function public.check_in_venue(uuid, uuid) to authenticated;
revoke execute on function public.check_out_venue(uuid) from public, anon;
grant execute on function public.check_out_venue(uuid) to authenticated;

-- 4. The public aggregate — never contains a per-user identity, safe to
--    expose broadly, same convention as venues/events.
create table if not exists public.grid_pulses (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid references public.venues(id) unique,
  lat float8 not null,
  lng float8 not null,
  pulse_count int not null default 0,
  age_18_20_count int not null default 0,
  age_21_plus_count int not null default 0,
  intensity text generated always as (
    case
      when pulse_count >= 30 then 'critical'
      when pulse_count >= 16 then 'high'
      when pulse_count >= 6 then 'medium'
      else 'low'
    end
  ) stored,
  last_updated timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '45 minutes'
);

alter table public.grid_pulses enable row level security;

drop policy if exists "grid pulses are public" on public.grid_pulses;
create policy "grid pulses are public" on public.grid_pulses for select
  to anon, authenticated
  using (true);
-- No insert/update/delete policy — written only by refresh_grid_pulses()
-- below, called via the service-role key from a Vercel cron route.

create or replace function public.refresh_grid_pulses() returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from grid_pulses where expires_at < now();
  insert into grid_pulses (venue_id, lat, lng, pulse_count, age_18_20_count, age_21_plus_count, last_updated, expires_at)
  select
    v.id, v.lat, v.lng,
    count(distinct c.user_id),
    count(distinct c.user_id) filter (where c.age_at_checkin between 18 and 20),
    count(distinct c.user_id) filter (where c.age_at_checkin >= 21),
    now(), now() + interval '45 minutes'
  from venues v
  join venue_checkins c on c.venue_id = v.id
  where c.checked_in_at > now() - interval '30 minutes'
    and (c.checked_out_at is null or c.checked_out_at > now() - interval '30 minutes')
  group by v.id, v.lat, v.lng
  on conflict (venue_id) do update set
    lat = excluded.lat, lng = excluded.lng,
    pulse_count = excluded.pulse_count,
    age_18_20_count = excluded.age_18_20_count,
    age_21_plus_count = excluded.age_21_plus_count,
    last_updated = excluded.last_updated,
    expires_at = excluded.expires_at;
end;
$$;

create index if not exists venue_checkins_user_idx on public.venue_checkins (user_id);
create index if not exists venue_checkins_venue_idx on public.venue_checkins (venue_id);
create index if not exists venue_checkins_checked_in_idx on public.venue_checkins (checked_in_at);
create index if not exists venue_checkins_chapter_idx on public.venue_checkins (chapter_id) where chapter_id is not null;
