-- TestFlight feedback (2026-08-27): "It doesn't show a picture or
-- description or the stadium" — the stadiums table never had columns for
-- either, so StadiumDetailView had nothing to render beyond the name.
-- Same "never fabricate" rule as venues: these stay NULL until backfilled
-- from a real source (Google Places, same as scripts/enrich-venues.ts).

ALTER TABLE stadiums ADD COLUMN IF NOT EXISTS image_url text;
ALTER TABLE stadiums ADD COLUMN IF NOT EXISTS description text;
