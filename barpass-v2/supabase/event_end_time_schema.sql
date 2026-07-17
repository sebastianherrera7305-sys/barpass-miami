-- Venue Intelligence Roadmap Phase 3: real event end times.
--
-- VenueEvent only ever had a start (`starts_at`) — every "is this event
-- still happening" check in the app assumed a fixed 4h duration
-- (VenueTimeStatus.defaultEventDuration). Nullable on purpose: most
-- existing/future event rows won't have a known end time either, and the
-- app must keep falling back to the 4h assumption rather than treat a
-- missing end time as "already over."

alter table public.events
    add column if not exists ends_at timestamptz;
