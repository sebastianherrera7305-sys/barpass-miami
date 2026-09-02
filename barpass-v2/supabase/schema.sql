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

-- RLS is row-level, not column-level — the policy above lets an owner PATCH
-- any column on their own row, including bpx_points. bpx_points isn't wired
-- to any app feature yet, but the public anon key ships inside the iOS
-- binary, so anyone can already PATCH it directly via the REST API today.
-- This trigger silently pins bpx_points to its previous value on any client
-- update, so a future points feature MUST go through a SECURITY DEFINER RPC
-- (same pattern as adjust_wallet_balance) instead of a direct client write.
create or replace function public.protect_profile_points()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.bpx_points is distinct from old.bpx_points then
    new.bpx_points := old.bpx_points;
  end if;
  return new;
end;
$$;

drop trigger if exists protect_profile_points_trigger on public.profiles;
create trigger protect_profile_points_trigger
  before update on public.profiles
  for each row
  execute function public.protect_profile_points();

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

-- TRIPS ─────────────────────────────────────────────────────
-- SUPERSEDED — do not run this block. The `public.trips` table actually
-- live in Supabase (verified via REST against the real DB) matches
-- trips_schema.sql (member_ids, co_organizer_ids, stops jsonb, invite_code,
-- timestamptz dates), not the `trip_data`/text-date shape this block used
-- to define. This block used `create table if not exists`, so once
-- trips_schema.sql's version existed, re-running this file was already a
-- silent no-op — but it's left here (commented, not deleted) so nobody
-- resurrects the wrong shape after a future `drop table public.trips`.
-- See trips_schema.sql for the real, current schema.
--
-- create table if not exists public.trips (
--   id uuid primary key default gen_random_uuid(),
--   user_id uuid not null references auth.users(id) on delete cascade,
--   title text not null,
--   destination_city text not null,
--   start_date text not null,
--   end_date text not null,
--   visibility text not null default 'private',
--   status text not null default 'planning',
--   trip_data jsonb not null default '{}',
--   created_at timestamptz not null default now(),
--   updated_at timestamptz not null default now()
-- );
--
-- alter table public.trips enable row level security;
--
-- create policy "manage own trips"
--   on public.trips for all
--   to authenticated
--   using (auth.uid() = user_id)
--   with check (auth.uid() = user_id);

-- SAVED PLANS (AI Concierge output) ───────────────────────────
-- `plan` is a whole `NightPlan` blob, shape unified 2026-09-01 (see
-- CLAUDE.md → "Plan Consolidation Roadmap") between the iOS app and the AI
-- concierge (this table's only two writers): { title, summary,
-- stops: [{ time, venueSlug, venueName, note, estimatedSpend }],
-- totalEstimate, insiderTip } — matches
-- src/features/ai/services/plan-schema.ts exactly. Being jsonb, this never
-- needed an ALTER TABLE for the shape change; it just started writing the
-- new fields. `id`/`user_id`/`title` are their own columns purely for RLS
-- and future listing/search, not a field-by-field mirror of the model.
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

-- PLAN CHAT CONVERSATIONS (Phase 1, 2026-09-02) ────────────────
-- Same jsonb-blob-per-row pattern as night_plans: `conversation` holds a
-- whole PlanConversation — id, title, every message (role/text/plan/
-- quickActions), currentPlan, timestamps — as one blob. `id`/`user_id`/
-- `title` are their own columns purely for RLS and listing past
-- conversations; the app never queries into individual messages
-- server-side, so no normalized messages table.
create table if not exists public.plan_conversations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null default '',
  conversation jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.plan_conversations enable row level security;

create policy "manage own plan conversations"
  on public.plan_conversations for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create index if not exists plan_conversations_user_updated_idx
  on public.plan_conversations (user_id, updated_at desc);

-- PLAN USAGE / FREE QUOTA (Phase 3, 2026-09-02) ────────────────
-- One row per signed-in user, resets automatically when `usage_date` no
-- longer matches "today" (UTC) — enforced in the RPCs below, not a cron
-- job. Guests have no server-side identity, so their usage is tracked
-- device-locally in UserDefaults instead (see PlanUsageService.swift);
-- this table only ever holds signed-in users' counts.
create table if not exists public.plan_usage (
  user_id uuid primary key references auth.users(id) on delete cascade,
  usage_date date not null default (now() at time zone 'utc')::date,
  message_count int not null default 0,
  updated_at timestamptz not null default now()
);

alter table public.plan_usage enable row level security;

create policy "manage own plan usage"
  on public.plan_usage for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Atomic read-and-increment — a plain client-side read-then-write would
-- race under concurrent taps; this is one upsert statement.
create or replace function public.increment_plan_usage()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  today date := (now() at time zone 'utc')::date;
  new_count int;
begin
  insert into public.plan_usage (user_id, usage_date, message_count, updated_at)
  values (auth.uid(), today, 1, now())
  on conflict (user_id) do update
    set message_count = case when public.plan_usage.usage_date = today then public.plan_usage.message_count + 1 else 1 end,
        usage_date = today,
        updated_at = now()
  returning message_count into new_count;
  return new_count;
end;
$$;

grant execute on function public.increment_plan_usage() to authenticated;

-- Read-only — today's count without incrementing, 0 if there's no row yet
-- or the stored row is from a previous day.
create or replace function public.get_plan_usage()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  today date := (now() at time zone 'utc')::date;
  cnt int;
begin
  select message_count into cnt from public.plan_usage
    where user_id = auth.uid() and usage_date = today;
  return coalesce(cnt, 0);
end;
$$;

grant execute on function public.get_plan_usage() to authenticated;

-- APP CONFIG (Phase 3, 2026-09-02) ──────────────────────────────
-- Small key/value store for values that need to change without an app
-- update — starts with just the Free daily Plan quota
-- (04_FREE_PLAN_SPEC.md: "The exact quota should be configurable from the
-- backend. Do not hardcode the number into the UI."). Readable by anyone,
-- including guests (anon key, no session) — nothing in here is
-- user-specific or sensitive.
create table if not exists public.app_config (
  key text primary key,
  value jsonb not null
);

alter table public.app_config enable row level security;

create policy "anyone can read app config"
  on public.app_config for select
  using (true);

insert into public.app_config (key, value)
values ('plan_free_daily_limit', '10')
on conflict (key) do nothing;

-- PLAN PREFERENCES (Fase 4 real, 2026-09-02) ────────────────────
-- Lightweight cross-conversation memory — 05_PREMIUM_AI_SPEC.md's "start
-- lightweight... do not build a complicated memory system in V1". One row
-- per user, `context` is a whole TripContext blob (intents/company/
-- inclusivePrefs/prompt) from the last plan-generating turn. Premium-only
-- by product decision (PlanView only reads/writes this for entitled users):
-- Free always starts a new conversation blank, Premium's context picker
-- pre-fills with what you picked last time — the actual, felt difference
-- between the two tiers, not just a higher usage cap.
create table if not exists public.plan_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  context jsonb not null,
  updated_at timestamptz not null default now()
);

alter table public.plan_preferences enable row level security;

create policy "manage own plan preferences"
  on public.plan_preferences for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Useful indexes ──────────────────────────────────────────────
create index if not exists venues_neighborhood_idx on public.venues (neighborhood);
create index if not exists venues_trending_idx on public.venues (is_trending) where is_trending;
create index if not exists events_venue_idx on public.events (venue_id, starts_at);
