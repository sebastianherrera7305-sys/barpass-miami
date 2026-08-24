-- Real event data from Ticketmaster Discovery API — never invented, never
-- guessed. Each event traces to its real Ticketmaster event id + ticket
-- URL. Synced periodically (see scripts/sync-stadium-events.ts), same
-- pattern as venue Google-sync (google_place_id, google_synced_at).

create table if not exists public.stadium_events (
  id uuid primary key default gen_random_uuid(),
  stadium_id uuid references public.stadiums(id) on delete cascade not null,
  ticketmaster_event_id text not null unique,
  name text not null,
  starts_at timestamptz not null,
  ticket_url text,
  image_url text,
  synced_at timestamptz not null default now()
);

alter table public.stadium_events enable row level security;
drop policy if exists "stadium events are public" on public.stadium_events;
create policy "stadium events are public" on public.stadium_events for select
  to anon, authenticated using (true);

create index if not exists stadium_events_stadium_idx on public.stadium_events (stadium_id);
create index if not exists stadium_events_starts_at_idx on public.stadium_events (starts_at);
