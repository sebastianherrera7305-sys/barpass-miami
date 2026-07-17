-- Real amenity/accessibility columns sourced from Google Places API v1.
-- Every column is nullable and BOOLEAN — NULL means "Google hasn't told us
-- yet", never "false". The UI must treat NULL as "don't show this badge",
-- not as a negative claim about the venue. Populated by
-- scripts/enrich-venues.ts, which only ever writes a value when Google's
-- response actually included it.
--
-- Deliberately NOT included (per the 2026-07-16 data audit): noise level,
-- LGBTQ+-friendliness, language support, dietary specifics beyond
-- vegetarian — none of these have a reliable Google Places field. Adding
-- them here would mean either fabricating values or shipping a column
-- that's always NULL and pretending it's meaningful.

alter table public.venues
    add column if not exists wheelchair_accessible   boolean,
    add column if not exists outdoor_seating         boolean,
    add column if not exists good_for_groups          boolean,
    add column if not exists good_for_watching_sports boolean,
    add column if not exists has_live_music            boolean,
    add column if not exists reservable               boolean,
    add column if not exists serves_vegetarian_food    boolean,
    add column if not exists restroom                  boolean,
    add column if not exists amenities_synced_at        timestamptz;
