-- Per-field provenance for venues: where each value came from.
--
-- WHY
-- Eight scripts write to `venues`. On 2026-09-01 an audit found that a
-- 2026-07-07 seed batch had written the identical value to 175 rows for
-- music_genres, dress_code, parking, best_arrival_time and peak_hours, and
-- nobody noticed for two months — because nothing recorded where a value came
-- from. Real and fabricated data were indistinguishable in the same column.
--
-- The risk is live, not historical: `enrich-venues.ts` writes `image_url`. If
-- it is re-run it will overwrite the pre-sized, key-free photo URLs generated
-- on 2026-09-01 with the 1.3MB unsized form, silently undoing that work. A
-- script that can read provenance can refuse to do that.
--
-- SHAPE
--   {
--     "music_genres": {"source": "manual_research", "at": "2026-09-01",
--                      "confidence": "high"},
--     "image_url":    {"source": "google_places", "at": "2026-09-01"}
--   }
--
-- CONVENTIONS
--   source       who produced the value: "google_places", "ticketmaster",
--                "manual_research", "seed", "user_report".
--   confidence   "high" | "medium" | "low". Omit when it does not apply
--                (a Google photo URL is not a judgement call).
--   at           ISO date the value was written.
--
-- An absent key means the origin is unknown — the default for anything
-- written before this column existed. That is honest: it does not claim the
-- value is fabricated, only that nobody recorded where it came from.
--
-- RULE FOR WRITERS
-- Before overwriting a field, read its entry. A broad automated pass must not
-- clobber a value whose source is "manual_research" or "user_report" — those
-- cost human effort and are more trustworthy than a re-scrape.
--
-- Idempotent, safe to re-run.

alter table public.venues
  add column if not exists field_sources jsonb not null default '{}'::jsonb;

comment on column public.venues.field_sources is
  'Per-field provenance: {"<column>": {"source": "...", "at": "YYYY-MM-DD", "confidence": "high|medium|low"}}. A field with an entry here was written deliberately from a named source — do not overwrite it with a broader/automated pass without checking. Absent key = unknown origin.';

-- GIN so "which venues have a researched genre" stays cheap as this grows.
create index if not exists venues_field_sources_idx
  on public.venues using gin (field_sources);

-- Verify:
--   select count(*) filter (where field_sources ? 'music_genres') as genres_traced,
--          count(*) filter (where field_sources ? 'image_url')    as photos_traced
--     from public.venues;
