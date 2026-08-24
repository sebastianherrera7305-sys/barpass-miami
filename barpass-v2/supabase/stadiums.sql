-- Interactive Venue Map — Phase 1 data model. A stadium has levels; each
-- level has real, sourced POIs (bars, concessions, merch, services). No
-- routing/3D geometry yet (see the phased Kimi research) — this is the
-- "browse by level, tap a POI, see info" MVP the phased brief scoped as
-- buildable today with public data alone.

create table if not exists public.stadiums (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  address text not null,
  lat float8,
  lng float8,
  source_url text not null,
  created_at timestamptz not null default now()
);

alter table public.stadiums enable row level security;
drop policy if exists "stadiums are public" on public.stadiums;
create policy "stadiums are public" on public.stadiums for select
  to anon, authenticated using (true);

create table if not exists public.stadium_pois (
  id uuid primary key default gen_random_uuid(),
  stadium_id uuid references public.stadiums(id) on delete cascade not null,
  level_name text not null,
  level_order int not null default 0,
  name text not null,
  poi_type text not null check (poi_type in (
    'bar', 'concession', 'merch', 'restroom', 'first_aid',
    'guest_services', 'elevator', 'entrance', 'other'
  )),
  section_or_concourse text,
  source_url text not null,
  confidence text not null default 'verified' check (confidence in ('verified', 'unverified')),
  created_at timestamptz not null default now()
);

alter table public.stadium_pois enable row level security;
drop policy if exists "stadium pois are public" on public.stadium_pois;
create policy "stadium pois are public" on public.stadium_pois for select
  to anon, authenticated using (true);

create index if not exists stadium_pois_stadium_idx on public.stadium_pois (stadium_id);
