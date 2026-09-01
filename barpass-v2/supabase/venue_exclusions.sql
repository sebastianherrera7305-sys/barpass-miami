-- Venues that exist and are open, but do not belong in a nightlife app.
--
-- `business_status` (from Google Places) answers "does this place still
-- exist" — it cannot answer "should this place be here at all". An airport
-- VIP lounge is genuinely OPERATIONAL; marking it CLOSED_PERMANENTLY to
-- hide it would put a false fact in the data. This column is the honest
-- home for that second question, and it records WHY so the decision can be
-- reviewed instead of silently disappearing a row.
--
-- Nothing is deleted: orders, passes and venue_posts reference venues, and
-- a hard delete would either cascade real records away or fail. Excluded
-- rows simply stop being served to the apps.
--
-- Sourced from per-venue research, 2026-09-01 (see the notes in each
-- update below — every one was verified against a primary source).

alter table public.venues add column if not exists excluded_reason text;

comment on column public.venues.excluded_reason is
  'Non-null means: do not surface in the apps. Free text explains why. NULL = normal, listed venue.';

create index if not exists venues_not_excluded_idx
  on public.venues (id) where excluded_reason is null;

-- Airport lounges: airside at MIA, not reachable as nightlife.
update public.venues set excluded_reason = 'Airport VIP lounge inside MIA, not a public nightlife venue'
 where name in ('Turkish Airlines Lounge - Concourse E', 'Turkish Airlines Lounge', 'Avianca VIP Lounge');

-- Not a bar/club at all.
update public.venues set excluded_reason = 'Open-air cinema, not a nightlife venue'
 where name = 'Rooftop Cinema Club South Beach';
update public.venues set excluded_reason = 'Retail smoke shop, not a nightlife venue'
 where name like 'Ark Smoke Shop%';

-- Outside the Miami nightlife footprint.
update public.venues set excluded_reason = 'Casino resort in Davie, ~40km outside Miami'
 where name = 'Seminole Hard Rock Hotel & Casino';
update public.venues set excluded_reason = 'Florida City, ~56km south of Miami'
 where name = 'Last Chance Bar & Package';

-- Location does not exist: the chain has no outlet in the listed area.
update public.venues set excluded_reason = 'No Coconut Grove location exists for this chain'
 where name in ('Earls Kitchen + Bar', 'Miller''s Ale House', 'Hole in the Wall');

-- Verify:
--   select name, type, excluded_reason from public.venues
--    where excluded_reason is not null order by name;
