-- ─────────────────────────────────────────────────────────────────────────
-- SECURITY FIX (audit 2026-09-16, finding #1 — medium):
-- 1,449 sorority/fraternity houses were handing out their street address and
-- exact coordinates to anyone holding the shipped anon key — no account, no
-- signup, one curl:
--
--   curl "$SUPABASE_URL/rest/v1/greek_chapters?select=fraternity_name,address,lat,lng" \
--        -H "apikey: $ANON_KEY"
--
-- The data itself is sourced from official university Greek Life pages, so
-- publishing the CHAPTER is fine — that is exactly what the directory is for.
-- Publishing the DOOR is not. A nightlife app whose map drops a pin on a
-- sorority house for an unauthenticated stranger is a stalking aid, and the
-- fact that each address was individually verified (address_verified) makes
-- it a better one than anything scraped.
--
-- What stays public:  name, chapter designation, university, council, status,
--                     the official source URL that proves the row is real,
--                     and the review flags.
-- What now needs a session: address, lat, lng, chapter_url.
--
-- (chapter_url is in the restricted set because a chapter's own site is the
-- other reliable route to its address and to its members' names.)
--
--
-- WHY NOT RLS
-- -----------
-- RLS is ROW-level. The "greek_chapters are public" policy in
-- greek_life_schema.sql is `using (true)` for anon and authenticated, and no
-- policy can hide a COLUMN. Column privileges are the only mechanism, same
-- as venue_media.user_id (venue_stories.sql) and venues.validation_secret
-- (venue_secrets_lockdown.sql).
--
-- THE TRAP THIS FILE IS WRITTEN AROUND
-- ------------------------------------
-- `revoke select (address) on public.greek_chapters from anon` IS A NO-OP.
-- Postgres checks the TABLE-level grant first and never consults the column
-- list when one exists. Supabase ships `grant select on all tables ... to
-- anon, authenticated`, so that table grant always exists. The only sequence
-- that works is: revoke the table, then grant back exactly the public
-- columns. That is what §2 does, and §3 proves it by behaviour — by actually
-- reading as `anon` — not by the fact that the SQL ran without error.
--
-- CLIENTS MUST NAME THEIR COLUMNS AFTER THIS.
-- `select=*` on greek_chapters becomes a 42501 for anon (and only returns
-- the restricted columns for authenticated). SupabaseGreekLifeRepository.swift
-- was changed in the same commit: it asks for the public column list with the
-- anon key and for the full list only when it has a real session.
--
-- Idempotent, safe to re-run. Run once in the Supabase SQL editor.
-- ─────────────────────────────────────────────────────────────────────────


-- ═══════════════════════════════════════════════════════════════════
-- 1. RLS stays exactly as it was
-- ═══════════════════════════════════════════════════════════════════
-- Every row is still visible to both roles; this file changes WHICH COLUMNS
-- of that row each role may read, nothing else. Restated here so re-running
-- greek_life_schema.sql after this file cannot silently drop the policy.

alter table public.greek_chapters enable row level security;

drop policy if exists "greek_chapters are public" on public.greek_chapters;
create policy "greek_chapters are public"
  on public.greek_chapters for select
  to anon, authenticated
  using (true);


-- ═══════════════════════════════════════════════════════════════════
-- 2. COLUMN PRIVILEGES — revoke the table, grant back the columns
-- ═══════════════════════════════════════════════════════════════════

revoke select on public.greek_chapters from anon;
revoke select on public.greek_chapters from authenticated;

-- anon: the directory, without the door.
grant select (
  id,
  university_id,
  fraternity_name,
  chapter_designation,
  council,
  status,
  official_source_url,
  address_verified,
  needs_review,
  review_reason,
  source_last_verified,
  created_at
) on public.greek_chapters to anon;

-- authenticated: the same, plus location and the chapter's own site.
grant select (
  id,
  university_id,
  fraternity_name,
  chapter_designation,
  council,
  status,
  official_source_url,
  address_verified,
  needs_review,
  review_reason,
  source_last_verified,
  created_at,
  chapter_url,
  address,
  lat,
  lng
) on public.greek_chapters to authenticated;

-- No write grants are touched: this table has no insert/update/delete policy
-- for either role and is written only by the research pipeline through the
-- service role, which bypasses both RLS and these grants.
--
-- Nothing else in the database reads these columns through a caller's
-- privileges: list_university_public_events (chapter_events_public.sql) and
-- check_profile_affiliation_consistency (profile_affiliation_consistency.sql)
-- are both SECURITY DEFINER, and the foreign keys pointing at
-- greek_chapters(id) are enforced by the system, not by SELECT privilege.


-- ═══════════════════════════════════════════════════════════════════
-- 3. VERIFY BY BEHAVIOUR, NOT BY "THE SQL RAN"
-- ═══════════════════════════════════════════════════════════════════
-- Reads the table as each role and asserts the four outcomes that matter.
-- If this block raises, the lockdown did NOT take effect — do not report the
-- finding as closed.

do $$
begin
  -- anon must be DENIED the restricted columns.
  set local role anon;
  begin
    perform address, lat, lng from public.greek_chapters limit 1;
    raise exception 'FAIL: anon can still read greek_chapters.address/lat/lng';
  exception when insufficient_privilege then
    raise notice 'OK: anon denied address/lat/lng';
  end;

  begin
    perform chapter_url from public.greek_chapters limit 1;
    raise exception 'FAIL: anon can still read greek_chapters.chapter_url';
  exception when insufficient_privilege then
    raise notice 'OK: anon denied chapter_url';
  end;

  -- ...and `select *` with it, which is how it would leak by accident.
  begin
    perform * from public.greek_chapters limit 1;
    raise exception 'FAIL: anon can still run select * on greek_chapters';
  exception when insufficient_privilege then
    raise notice 'OK: anon denied select *';
  end;

  -- anon must STILL be able to read the directory itself.
  begin
    perform id, fraternity_name, council, status, university_id
    from public.greek_chapters limit 1;
    raise notice 'OK: anon can still read the public directory columns';
  exception when insufficient_privilege then
    raise exception 'FAIL: the public directory is broken for anon';
  end;

  -- authenticated must keep full access (the app needs the map pin).
  set local role authenticated;
  begin
    perform address, lat, lng, chapter_url from public.greek_chapters limit 1;
    raise notice 'OK: authenticated can read address/lat/lng/chapter_url';
  exception when insufficient_privilege then
    raise exception 'FAIL: authenticated lost access to address/lat/lng/chapter_url';
  end;

  reset role;
  raise notice 'greek_chapters lockdown verified.';
end $$;

-- Second opinion, straight from the catalog — the exact column list each
-- role holds. anon must not list address, lat, lng or chapter_url.
--   select grantee, string_agg(column_name, ', ' order by column_name)
--   from information_schema.column_privileges
--   where table_schema = 'public' and table_name = 'greek_chapters'
--     and privilege_type = 'SELECT' and grantee in ('anon', 'authenticated')
--   group by grantee;
