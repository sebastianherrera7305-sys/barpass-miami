-- Let the venue table say "we don't know".
--
-- WHY THIS EXISTS
-- dress_code, parking, best_arrival_time, peak_hours, popular_drinks and
-- vibes are all NOT NULL. An enrichment script that does not know a venue's
-- dress code therefore CANNOT leave it empty — the schema forces it to write
-- something. That is not a hypothetical: 175 rows seeded on 2026-07-07 all
-- carry the identical values
--
--   dress_code        = 'Upscale — dress to impress'   (1 distinct value / 175)
--   parking           = 'Valet available'              (1 distinct value / 175)
--   best_arrival_time = '11:00 PM'                     (1 distinct value / 175)
--   peak_hours        = '12 AM – 3 AM'                 (1 distinct value / 175)
--
-- for sports bars, a brewery and nightclubs alike, and they were the ONLY
-- rows with any value in those columns — so both apps rendered fabricated
-- data as the sole source of truth on the venue detail screen. The same
-- batch is where the fabricated ['hip_hop','house'] music_genres came from.
--
-- Making unknown representable is the structural fix. The values themselves
-- have already been cleared to '' (a workaround for the constraint); after
-- this migration they should be NULL, which is the honest state, and code
-- can distinguish "no data" from "deliberately empty".
--
-- Idempotent, safe to re-run.

alter table public.venues alter column dress_code        drop not null;
alter table public.venues alter column parking           drop not null;
alter table public.venues alter column best_arrival_time drop not null;
alter table public.venues alter column peak_hours        drop not null;
alter table public.venues alter column popular_drinks    drop not null;
alter table public.venues alter column vibes             drop not null;

-- Normalise the placeholders written under the old constraint.
update public.venues set dress_code        = null where dress_code = '';
update public.venues set parking           = null where parking = '';
update public.venues set best_arrival_time = null where best_arrival_time = '';
update public.venues set peak_hours        = null where peak_hours = '';
-- popular_drinks is a `json` column, and json has no `=` operator in
-- Postgres — comparing it to '' also fails as invalid JSON syntax. Cast to
-- text. (Getting this wrong aborts the whole script: the Supabase SQL editor
-- runs it in one transaction, so the ALTERs above roll back with it.)
update public.venues set popular_drinks    = null where popular_drinks::text = '[]';
update public.venues set vibes             = null where cardinality(vibes) = 0;

-- crowd_level is 'steady' for all 1846 rows — there is no live busyness
-- source, so it is a constant pretending to be a reading. The crowd bar was
-- already removed from the cards for this reason; the column is left in place
-- for now rather than dropped, but nothing should read it as a real signal.

comment on column public.venues.dress_code is
  'NULL = unknown. Never invent: a value here is shown to users as fact.';
comment on column public.venues.crowd_level is
  'NOT a real signal: constant "steady" for every row, no live source. Do not display.';

-- Verify:
--   select count(*) filter (where dress_code is null) as unknown_dress,
--          count(distinct dress_code)                as distinct_dress
--     from public.venues;
