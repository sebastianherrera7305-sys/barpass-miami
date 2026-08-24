-- Venue Owner Dashboard: let a venue owner manage their own venue's events
-- and promos, instead of the dashboard being read-only.
--
-- Today the only "auth" on /dashboard is a shared secret per venue
-- (venue_secrets, see venue_secrets_lockdown.sql) used solely to view
-- today's stats — there is no table connecting a real Supabase Auth user
-- to "this is their venue," and `events` has no INSERT/UPDATE/DELETE policy
-- at all (`promos` doesn't exist yet). This migration adds both, scoped by
-- real Supabase Auth (auth.uid()) so RLS — not app code — enforces that an
-- owner can only write their own venue's rows.
--
-- venue_id is `uuid` (not `text`) on both new tables, matching
-- public.venues.id's actual type (uuid, schema.sql:10) rather than the
-- text id used elsewhere for e.g. Stripe pass venueId strings.
--
-- Provisioning a venue owner is a deliberate manual step in this pass —
-- no self-signup flow. BarPass ops runs, per new owner (after the user has
-- signed up once via Supabase Auth so auth.users has a row for them):
--
--   insert into public.venue_owners (user_id, venue_id, role)
--   values ('<auth.users.id>', '<venues.id>', 'owner');
--
-- Safe to run multiple times — every statement is idempotent.

-- VENUE OWNERS ────────────────────────────────────────────────
create table if not exists public.venue_owners (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) not null,
  venue_id uuid references public.venues(id) not null,
  role text not null default 'owner',
  created_at timestamptz not null default now(),
  unique (user_id, venue_id)
);

alter table public.venue_owners enable row level security;

-- Owners can see which venues they're linked to. No public insert/update/
-- delete policy — ops provisions rows directly in Supabase (service role
-- bypasses RLS), so there is deliberately no self-signup surface here.
drop policy if exists "read own venue links" on public.venue_owners;
create policy "read own venue links"
  on public.venue_owners for select
  to authenticated
  using (auth.uid() = user_id);

-- PROMOS ──────────────────────────────────────────────────────
create table if not exists public.promos (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid references public.venues(id) not null,
  title text not null,
  description text,
  starts_at timestamptz not null,
  ends_at timestamptz,
  discount_text text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.promos enable row level security;

-- Public read, same as events — promos are consumer-visible marketing
-- content, not staff-only data.
drop policy if exists "promos are public" on public.promos;
create policy "promos are public"
  on public.promos for select
  to anon, authenticated
  using (true);

drop policy if exists "owners manage own venue promos" on public.promos;
create policy "owners manage own venue promos"
  on public.promos for insert
  to authenticated
  with check (
    exists (
      select 1 from public.venue_owners vo
      where vo.venue_id = promos.venue_id and vo.user_id = auth.uid()
    )
  );

drop policy if exists "owners update own venue promos" on public.promos;
create policy "owners update own venue promos"
  on public.promos for update
  to authenticated
  using (
    exists (
      select 1 from public.venue_owners vo
      where vo.venue_id = promos.venue_id and vo.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.venue_owners vo
      where vo.venue_id = promos.venue_id and vo.user_id = auth.uid()
    )
  );

drop policy if exists "owners delete own venue promos" on public.promos;
create policy "owners delete own venue promos"
  on public.promos for delete
  to authenticated
  using (
    exists (
      select 1 from public.venue_owners vo
      where vo.venue_id = promos.venue_id and vo.user_id = auth.uid()
    )
  );

-- EVENTS — add write policies (SELECT already exists in schema.sql) ────
drop policy if exists "owners manage own venue events" on public.events;
create policy "owners manage own venue events"
  on public.events for insert
  to authenticated
  with check (
    exists (
      select 1 from public.venue_owners vo
      where vo.venue_id = events.venue_id and vo.user_id = auth.uid()
    )
  );

drop policy if exists "owners update own venue events" on public.events;
create policy "owners update own venue events"
  on public.events for update
  to authenticated
  using (
    exists (
      select 1 from public.venue_owners vo
      where vo.venue_id = events.venue_id and vo.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.venue_owners vo
      where vo.venue_id = events.venue_id and vo.user_id = auth.uid()
    )
  );

drop policy if exists "owners delete own venue events" on public.events;
create policy "owners delete own venue events"
  on public.events for delete
  to authenticated
  using (
    exists (
      select 1 from public.venue_owners vo
      where vo.venue_id = events.venue_id and vo.user_id = auth.uid()
    )
  );

-- Indexes ─────────────────────────────────────────────────────
create index if not exists venue_owners_user_idx on public.venue_owners (user_id);
create index if not exists venue_owners_venue_idx on public.venue_owners (venue_id);
create index if not exists promos_venue_idx on public.promos (venue_id, starts_at);
