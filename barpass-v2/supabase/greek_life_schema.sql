-- Greek Life directory: City -> University -> Council -> Chapter.
-- Every chapter row must trace back to a real, official source
-- (official_source_url is NOT NULL) — this table is never allowed to hold
-- an invented chapter. Written for a research pipeline that searches each
-- university's official Greek Life / IFC / NPHC / MGC pages, extracts real
-- chapters, and never assumes a national fraternity exists at a school just
-- because it exists elsewhere.
--
-- Idempotent, safe to re-run.

create table if not exists public.universities (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  short_name text,
  city text not null,
  state text,
  country text not null default 'US',
  official_url text,
  greek_life_url text,
  lat double precision,
  lng double precision,
  -- Only real, sourced facts (e.g. "IFC governs 26 fraternities per the
  -- official Greek Life office") — never a vibe/marketing description.
  party_life_notes text,
  source_last_verified timestamptz,
  created_at timestamptz not null default now(),
  unique (name, city)
);

create table if not exists public.greek_chapters (
  id uuid primary key default gen_random_uuid(),
  university_id uuid references public.universities(id) not null,
  fraternity_name text not null,
  chapter_designation text,
  council text not null check (council in ('IFC', 'NPHC', 'MGC', 'Panhellenic', 'Other')),
  -- 'active' only when the official source shows current evidence; every
  -- other case (source is silent, ambiguous, or shows a past/suspended
  -- state) is 'unknown', never defaulted to 'active'.
  status text not null default 'unknown' check (status in ('active', 'suspended', 'inactive', 'historical', 'unknown')),
  official_source_url text not null,
  chapter_url text,
  -- address/lat/lng only populated once the address itself has been
  -- independently verified as belonging to this chapter — never lifted
  -- from a generic Google Places address match.
  address text,
  lat double precision,
  lng double precision,
  address_verified boolean not null default false,
  -- Contradictory sources get flagged here for a human decision instead of
  -- the pipeline picking one arbitrarily.
  needs_review boolean not null default false,
  review_reason text,
  source_last_verified timestamptz not null default now(),
  created_at timestamptz not null default now()
);

alter table public.universities enable row level security;
alter table public.greek_chapters enable row level security;

drop policy if exists "universities are public" on public.universities;
create policy "universities are public"
  on public.universities for select
  to anon, authenticated
  using (true);

drop policy if exists "greek_chapters are public" on public.greek_chapters;
create policy "greek_chapters are public"
  on public.greek_chapters for select
  to anon, authenticated
  using (true);

-- No public insert/update/delete policy on either table — this data is
-- written only by the verified research pipeline via the service role key,
-- same convention as venues/events.

create index if not exists universities_city_idx on public.universities (city);
create index if not exists greek_chapters_university_idx on public.greek_chapters (university_id);
create index if not exists greek_chapters_council_idx on public.greek_chapters (council);
