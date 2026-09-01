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

-- ── Applied 2026-09-01 after per-venue research of all 182 Miami venues.
-- Kept here so the exclusion set is reproducible from source.

update public.venues set excluded_reason = 'Coordinates put it ~418km from Ann Arbor: wrong city assignment'
  where name = 'Kilroy''s on Kirkwood' and city = 'Ann Arbor';
update public.venues set excluded_reason = 'Coordinates put it ~815km from Chapel Hill: wrong city assignment'
  where name = 'Echelon Kitchen and Bar' and city = 'Chapel Hill';
update public.venues set excluded_reason = 'Coordinates put it ~255km from College Station: wrong city assignment'
  where name = 'The Village Coffee by Altara' and city = 'College Station';
update public.venues set excluded_reason = 'Airport VIP lounge (Amex, LAS), not a public nightlife venue'
  where name = 'Centurion Lounge' and city = 'Las Vegas';
update public.venues set excluded_reason = 'Retail smoke shop, not a nightlife venue'
  where name = 'Ark Smoke Shop Biscayne - Nature Bar & Lounge' and city = 'Miami';
update public.venues set excluded_reason = 'Retail smoke shop, not a nightlife venue'
  where name = 'Ark Smoke Shop South Miami - Nature Bar & Lounge' and city = 'Miami';
update public.venues set excluded_reason = 'Airport VIP lounge inside MIA, not a public nightlife venue'
  where name = 'Avianca VIP Lounge' and city = 'Miami';
update public.venues set excluded_reason = 'Permanently closed (Yelp); site defunct'
  where name = 'BLUME Nightclub' and city = 'Miami';
update public.venues set excluded_reason = 'Guided pub-crawl tour product, not a venue'
  where name = 'Bar Crawl Miami' and city = 'Miami';
update public.venues set excluded_reason = 'Relaunched as a private-events venue; the public lounge is closed'
  where name = 'Cafeina Wynwood - Event Venue in Miami' and city = 'Miami';
update public.venues set excluded_reason = 'Promoter LLC registered at a residential apartment, not a venue'
  where name = 'Elite Miami nightlife Ent' and city = 'Miami';
update public.venues set excluded_reason = 'Airport VIP lounge inside MIA (Concourse J), not a public nightlife venue'
  where name = 'LATAM Lounge Miami' and city = 'Miami';
update public.venues set excluded_reason = 'Florida City, ~56km south of Miami'
  where name = 'Last Chance Bar & Package' and city = 'Miami';
update public.venues set excluded_reason = 'Yacht charter operation, not a fixed venue'
  where name = 'Miami Beach Yacht Party & Club' and city = 'Miami';
update public.venues set excluded_reason = 'Concierge booking service, not a venue'
  where name = 'Night Out LLC - Miami NightLife Concierge' and city = 'Miami';
update public.venues set excluded_reason = 'Not a real business: junk directory record'
  where name = 'Nightclubs in Miami' and city = 'Miami';
update public.venues set excluded_reason = 'Exact duplicate of Purobar Lounge (same address 2523 NE 2nd Ave and phone)'
  where name = 'Puro bar by la licorera' and city = 'Miami';
update public.venues set excluded_reason = 'No such venue exists; mobile bartending personal brand'
  where name = 'Raise the Bar with Britt' and city = 'Miami';
update public.venues set excluded_reason = 'Open-air cinema, not a nightlife venue'
  where name = 'Rooftop Cinema Club South Beach' and city = 'Miami';
update public.venues set excluded_reason = 'Promoter/VIP concierge company at an office unit, not a venue'
  where name = 'Royale Society Hospitality' and city = 'Miami';
update public.venues set excluded_reason = 'Permanently closed since 2025'
  where name = 'Salt Kitchen & Lounge' and city = 'Miami';
update public.venues set excluded_reason = 'Casino resort in Davie, ~40km outside Miami'
  where name = 'Seminole Hard Rock Hotel & Casino' and city = 'Miami';
update public.venues set excluded_reason = 'Lounge aboard the cruise ship Celebrity Millennium, not a land venue'
  where name = 'Sky Lounge - Celebrity Millennium' and city = 'Miami';
update public.venues set excluded_reason = 'Promoter/party-bus service reselling entry to other clubs, not a venue'
  where name = 'South Beach Nightclubs' and city = 'Miami';
update public.venues set excluded_reason = 'Historic bar closed 2014 and demolished; the Kush tribute is now rebranded and listed closed'
  where name = 'Tobacco Road' and city = 'Miami';
update public.venues set excluded_reason = 'Airport VIP lounge inside MIA, not a public nightlife venue'
  where name = 'Turkish Airlines Lounge' and city = 'Miami';
update public.venues set excluded_reason = 'Airport VIP lounge inside MIA, not a public nightlife venue'
  where name = 'Turkish Airlines Lounge - Concourse E' and city = 'Miami';
update public.venues set excluded_reason = 'Airport VIP lounge inside MIA, not a public nightlife venue'
  where name = 'Turkish Airlines Lounge - Concourse H' and city = 'Miami';
update public.venues set excluded_reason = 'Promoter/concierge selling packages into other clubs, not a venue'
  where name = 'VIP South Beach Miami Nightlife - Nightclub Party Packages' and city = 'Miami';
update public.venues set excluded_reason = 'Aloft in-house bar brand; no Aloft exists in Coconut Grove'
  where name = 'WXYZ Bar & Lounge' and city = 'Miami';
update public.venues set excluded_reason = 'Permanently closed (Yelp); also wrong neighborhood'
  where name = 'Wasska Lounge' and city = 'Miami';
update public.venues set excluded_reason = 'Retail smoke shop, not a nightlife venue'
  where name = 'LIONSDELIVER Smoke Shop' and city = 'State College';
