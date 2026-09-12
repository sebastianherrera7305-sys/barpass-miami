-- Drinks pipeline cleanup — audit of 2026-09-12.
--
-- WHAT THE AUDIT FOUND (live DB, 1,871 rows / 1,749 served)
--   188 served venues carry popular_drinks with prices; ALL 188 have provenance
--   (field_sources.popular_drinks → the venue's own website), 0 items at $0,
--   0 identical lists copied across venues. Every stored price was re-checked
--   against its source page today: 203 of 212 rows with drinks still match
--   verbatim. The rest are handled below.
--
-- EVERY UPDATE IS BY id. Names repeat across (and within) cities — updating by
-- name once excluded three legitimate Miller's Ale House rows.
--
-- Idempotent, safe to re-run. Nothing here deletes a row.

begin;

-- ─────────────────────────────────────────────────────────────
-- 1. Two drink lists that can no longer be verified against their source.
--    The value is cleared; the provenance entry is kept and marked so the
--    next `extract:menus --only <id>` run re-reads the real menu.
-- ─────────────────────────────────────────────────────────────

-- Phyrst (State College): stored "Skinny Bitch $4.5 / Skinny Marg $4.5 /
-- Irish Car Bomb $8 / Stars & Stripes Bomb $8 / Purple Gatorade $6". The site
-- today prints "$3 Skinny Bitch | $3 Skinny Margs | $6 Irish Car Bombs | $4
-- Purple Gatorade" and has no "Stars & Stripes Bomb" at all. Whatever the
-- cause (menu change or mis-read), the stored numbers are wrong now.
update public.venues
   set popular_drinks = null,
       field_sources = jsonb_set(
         coalesce(field_sources, '{}'::jsonb),
         '{popular_drinks}',
         coalesce(field_sources->'popular_drinks', '{}'::jsonb)
           || '{"result":"unverifiable","result_at":"2026-09-12","result_notes":"Stored prices no longer appear on phyrst.com (site prints $3, not $4.5). Cleared pending re-extraction."}'::jsonb)
 where id = '3204f3d9-0cda-414e-8681-45e311a6f32a';

-- Attic Bar & Bistro (Boulder): stored "Drafts $5; Wells $5". The whole site
-- today contains exactly one price ("$12 Pitcher of Coors 9-Close"); neither
-- item nor price is on it. The 2026-09-08 check accepted any "$5" anywhere
-- in the page text, which is how this got through.
update public.venues
   set popular_drinks = null,
       field_sources = jsonb_set(
         coalesce(field_sources, '{}'::jsonb),
         '{popular_drinks}',
         coalesce(field_sources->'popular_drinks', '{}'::jsonb)
           || '{"result":"unverifiable","result_at":"2026-09-12","result_notes":"Neither item nor price appears anywhere on atticbistro.com. Cleared pending re-extraction."}'::jsonb)
 where id = 'b2261c7e-de06-4bad-bb98-49a6d5aa4eaa';

-- ─────────────────────────────────────────────────────────────
-- 2. happy_hour_until values the old parser got wrong.
--    The parser took the LAST number in the window text; it mis-read "12am"
--    as noon, "8-10" as 10 in the morning, "9PM-Close" as 9 PM (the start),
--    and collapsed multi-window strings ("Mon-Fri 3-6 | Sat-Sun 4-7") into
--    one number. The fixed parser (scripts/drink-menu-rules.ts, unit-tested)
--    was run over the verbatim text stored in provenance: 82 of 93 values
--    are unchanged, 2 are corrected, 9 are cleared because the site states
--    a window that is not one clock time. The verbatim text stays in
--    field_sources.happy_hour_until.notes for a future days-aware column.
-- ─────────────────────────────────────────────────────────────

-- 2a. Corrections (the site is unambiguous; only the arithmetic was wrong).
update public.venues set happy_hour_until = '22:00'   -- "Sun, Tues-Thurs 8-10" (was 10:00)
 where id = '5484c3f4-1df6-46eb-8601-02d982506f62';   -- Oddfellows, Las Vegas
update public.venues set happy_hour_until = '00:00'   -- "Sun-Thu 10pm-12am" (was 12:00)
 where id = '3204f3d9-0cda-414e-8681-45e311a6f32a';   -- Phyrst, State College
update public.venues set happy_hour_until = '00:00'   -- "Tues-Sat 9:00pm-12:00am" (was 12:00)
 where id = 'e202dd10-6420-4302-9196-c892d0995386';   -- The Shandygaff, State College

-- 2b. Cleared: the window is real but has no single end time.
update public.venues
   set happy_hour_until = null,
       field_sources = jsonb_set(
         coalesce(field_sources, '{}'::jsonb),
         '{happy_hour_until}',
         coalesce(field_sources->'happy_hour_until', '{}'::jsonb)
           || '{"result":"window_not_single_clock_time","result_at":"2026-09-12"}'::jsonb)
 where id in (
   '238e34d1-ca62-4a94-a74b-17549b8ec24d',  -- American Social, Miami: "Mon-Fri 4pm-7pm; Sun-Wed 10pm-close" (was 19:00)
   '3e89375b-1214-462a-be10-adfef7de4bd8',  -- Charlie Park, Tallahassee: "Mon-Fri 4-7pm; Sat 11am-4pm" (was 16:00)
   'cd40d49f-338a-43e3-9c0b-4416cced9d4d',  -- Doggie's Pub, State College: four different windows by day (was 22:00)
   '19d92908-6257-47c7-856b-ca34c43dc778',  -- HopCat, Ann Arbor: "3PM-5:30 PM | 9PM-Close" (was 21:00 = the START of the late window)
   '0f6a737e-1d94-4bf8-ac16-21ff7fd2f336',  -- Howl at the Moon, Chicago: "7-10pm (Thu), 6-9pm (Fri), 7-9pm (Sat)" (was 21:00)
   '313bb131-8bbf-467c-ac20-5e97a7fcc069',  -- Potbellys, Tallahassee: "5PM-6PM, 6PM-7PM, 7:30PM" tiered specials (was 19:30)
   'b470fe71-37fa-4a89-8adc-5769bd76ed81',  -- Superbueno, New York: "Mon-Thu 4-7pm | Fri 2pm-7pm 4-7pm" (was 19:00)
   '6b87f620-ac72-4873-8b6f-ef755ace50bd',  -- The Malt House, New York: "Mon-Fri 3-6pm | Sat-Sun 4-7pm" (was 19:00)
   '0d88385a-b1e6-4037-982d-9bd5446a1046'   -- Twin Peaks, Baton Rouge: "3-7pm, 10pm-11pm" (was 23:00)
 );

-- ─────────────────────────────────────────────────────────────
-- 3. 23 rows hold an empty array '[]' instead of NULL. Harmless to render,
--    but venue_unknown_is_representable.sql made NULL the one honest "unknown"
--    and these were written after that migration ran. All 23 are Gainesville
--    (+ Factory Town, Miami) and have no provenance entry.
-- ─────────────────────────────────────────────────────────────
update public.venues
   set popular_drinks = null
 where popular_drinks::text = '[]'
   and id in (
   'cd4c7544-0ce0-40ce-a933-5e5045c4aeca', '0906619a-192b-425f-a684-a6a3297df5cb',
   'c24d5b22-cbc4-4b32-aae3-3a1b44149649', '67fbd82e-5686-442f-9160-b13da8a2fdb5',
   '971763a7-8655-4501-9c6a-28386bce69b2', 'dfeef7e2-509a-42be-a72d-01a087e07e47',
   '50f22f31-926c-4732-8ca7-4a0a5fdfab4d', '9b2975cb-8b10-49ec-b072-9da6ba2a7793',
   '5a58fbe5-1ce3-4c14-98c8-d46afec993e2', '7714f601-3289-428b-a7b9-87830130fb14',
   'd7cc97cb-177e-44b2-be74-8eef387ba0fc', 'e01a7736-79bd-452d-a23c-118ff350446b',
   'bd8414cb-bd0d-47b4-9fd4-e4ed3c755420', '54a75264-4ec1-44fc-abb9-83956d70df03',
   'd71f0c19-9c4d-419e-bdc5-44f66b4661b9', '2e962b8a-ea9e-4a96-9cb0-ff8a794ef806',
   '1e9980dc-75f4-470c-9dd6-a2eaad34bb1c', 'be6a6814-c1d0-4376-857d-3324e6d057b6',
   'c181c556-4412-45e0-8c65-728d3b9b647c', 'ceb06e9b-5dec-401f-9c5c-88a7c12afead',
   '191787ef-6f49-4518-a81b-1ed303580f5d', 'eac75cff-100e-47f5-ac76-0e622fdb2994',
   'babbdf2d-9d78-429f-bd6e-0b475790aebb'
 );

-- ─────────────────────────────────────────────────────────────
-- 4. MODE Downtown Miami is business_status = CLOSED_PERMANENTLY and still
--    carries a drink list + happy hour. Every read already filters it out;
--    clearing keeps a dead venue from ever counting as "priced" in stats.
-- ─────────────────────────────────────────────────────────────
update public.venues
   set popular_drinks = null, happy_hour_until = null
 where id = '76ae2b6c-5aa3-4a77-92a2-c41cec003ab5'
   and business_status = 'CLOSED_PERMANENTLY';

commit;

-- Verify (expected after running: priced 186, hh 84, empty_arrays 0):
--   select
--     count(*) filter (where jsonb_typeof(popular_drinks::jsonb) = 'array'
--                        and jsonb_array_length(popular_drinks::jsonb) > 0) as priced,
--     count(*) filter (where happy_hour_until is not null)                   as hh,
--     count(*) filter (where popular_drinks::text = '[]')                    as empty_arrays
--   from public.venues
--   where excluded_reason is null
--     and (business_status is null or business_status <> 'CLOSED_PERMANENTLY');
--
-- To restore Phyrst / Attic from their real menus once the site is readable:
--   npm run extract:menus -- --apply --only 3204f3d9-0cda-414e-8681-45e311a6f32a
--   npm run extract:menus -- --apply --only b2261c7e-de06-4bad-bb98-49a6d5aa4eaa
