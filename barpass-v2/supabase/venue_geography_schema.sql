-- Multi-city readiness (Venue Intelligence Roadmap, Phase 2).
--
-- This is schema/model work only — it does NOT seed any non-Miami venues.
-- Every existing row genuinely is in Miami today, so backfilling
-- city='Miami', country='US', timezone='America/New_York' for current rows
-- is a true fact, not an invented default; NOT NULL + a Miami default keeps
-- future inserts honest without silently defaulting a real other-city venue
-- to the wrong place (whoever inserts a new venue must pass its real city).

alter table public.venues
    add column if not exists city     text not null default 'Miami',
    add column if not exists country  text not null default 'US',
    -- IANA identifier (e.g. "America/New_York") — lets VenueTimeStatus-style
    -- open/close and event-status logic work correctly once venues exist
    -- outside the app's current single implicit timezone.
    add column if not exists timezone text not null default 'America/New_York';

create index if not exists venues_city_idx on public.venues (city);
