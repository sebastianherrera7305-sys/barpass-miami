-- ─────────────────────────────────────────────────────────────
-- BarPass V2 — Supabase schema
-- Run in the Supabase SQL editor (project: barpass).
-- RLS is ON for every table: security lives in the database, so
-- web, iOS and future clients share identical guarantees.
-- ─────────────────────────────────────────────────────────────

-- VENUES ──────────────────────────────────────────────────────
create table if not exists public.venues (
  id uuid primary key default gen_random_uuid(),
  slug text unique not null,
  name text not null,
  type text not null check (type in
    ('club','rooftop','bar','lounge','sports_bar','restaurant','brewery')),
  neighborhood text not null,
  address text not null,
  lat double precision not null,
  lng double precision not null,
  hook text not null default '',
  description text not null default '',
  rating numeric(2,1) not null default 0,
  review_count int not null default 0,
  cover_men int,
  cover_women int,
  price_tier smallint not null default 2 check (price_tier between 1 and 4),
  avg_spend int not null default 0,
  open_time text not null,
  close_time text not null,
  happy_hour_until text,
  music_genres text[] not null default '{}',
  vibes text[] not null default '{}',
  dress_code text not null default '',
  parking text not null default '',
  crowd_level text not null default 'steady',
  best_arrival_time text not null default '',
  peak_hours text not null default '',
  popular_drinks jsonb not null default '[]',
  emoji text not null default '🍸',
  image_url text,
  instagram_handle text,
  is_trending boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.venues enable row level security;

create policy "venues are public"
  on public.venues for select
  to anon, authenticated
  using (true);

-- EVENTS ──────────────────────────────────────────────────────
create table if not exists public.events (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references public.venues(id) on delete cascade,
  title text not null,
  description text not null default '',
  starts_at timestamptz not null,
  cover_price int,
  created_at timestamptz not null default now()
);

alter table public.events enable row level security;

create policy "events are public"
  on public.events for select
  to anon, authenticated
  using (true);

-- PROFILES ────────────────────────────────────────────────────
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  avatar_url text,
  bpx_points int not null default 0,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "read own profile"
  on public.profiles for select
  to authenticated
  using (auth.uid() = id);

create policy "update own profile"
  on public.profiles for update
  to authenticated
  using (auth.uid() = id);

-- Auto-create profile on signup
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'name', 'Nightlifer'));
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- FAVORITES ───────────────────────────────────────────────────
create table if not exists public.favorites (
  user_id uuid not null references auth.users(id) on delete cascade,
  venue_id uuid not null references public.venues(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, venue_id)
);

alter table public.favorites enable row level security;

create policy "manage own favorites"
  on public.favorites for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- SAVED PLANS (AI Concierge output) ───────────────────────────
create table if not exists public.night_plans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  plan jsonb not null,
  created_at timestamptz not null default now()
);

alter table public.night_plans enable row level security;

create policy "manage own plans"
  on public.night_plans for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Useful indexes ──────────────────────────────────────────────
create index if not exists venues_neighborhood_idx on public.venues (neighborhood);
create index if not exists venues_trending_idx on public.venues (is_trending) where is_trending;
create index if not exists events_venue_idx on public.events (venue_id, starts_at);
