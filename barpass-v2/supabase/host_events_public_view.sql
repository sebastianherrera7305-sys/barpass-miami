-- ─────────────────────────────────────────────────────────────────────────
-- SECURITY FIX (audit 2026-09-16, finding #2 — low):
-- every published host event ships its organiser's auth.users UUID.
--
--   curl "$SUPABASE_URL/rest/v1/host_events?select=host_id&status=eq.published" \
--        -H "apikey: $ANON_KEY"
--
-- gives a clean, deduplicable list of real user ids. The ORGANISER being
-- public is correct and deliberate (host_events_schema.sql §3 says so: it is
-- the name on the flyer). The UUID is not the organiser — it is the primary
-- key of that person's account, and once it is enumerable it becomes a join
-- key: every future table keyed on user_id gets probed with it, and any
-- endpoint that takes a user id is suddenly addressable for real people
-- instead of random guesses. Nothing in the product needs it client-side.
--
-- THIS FILE ONLY ADDS THE VIEW (§1). It changes no existing privilege, so it
-- cannot break the build currently in flight. §2 is the follow-up that
-- actually closes the leak, and must not run until the clients read from the
-- view — it is left commented out on purpose.
--
-- Idempotent, safe to re-run. Run in the Supabase SQL editor.
-- ─────────────────────────────────────────────────────────────────────────


-- ═══════════════════════════════════════════════════════════════════
-- 1. THE PUBLIC VIEW — every column of a published event except host_id
-- ═══════════════════════════════════════════════════════════════════
-- SECURITY DEFINER (security_invoker = false), the same choice venue_stories
-- makes: the view must keep working after §2 revokes anon's access to the
-- underlying table. Because RLS on host_events is therefore NOT consulted,
-- the `status = 'published'` filter lives in the view body itself — drafts
-- and cancelled events must never appear here, and there is no policy behind
-- this to catch it if the WHERE clause is ever dropped.

drop view if exists public.host_events_public;
create view public.host_events_public
with (security_invoker = false) as
select
  e.id,
  e.venue_id,
  e.title,
  e.description,
  e.starts_at,
  e.ends_at,
  e.status,
  e.attendee_list_public,
  e.claim_window_minutes,
  e.cover_image_url,
  e.cancelled_at,
  e.created_at
from public.host_events e
where e.status = 'published';

comment on view public.host_events_public is
  'Published host events without host_id. The organiser is public; the '
  'organiser''s account UUID is not. SECURITY DEFINER, so the published-only '
  'filter is in the view body, not in RLS.';

revoke all on public.host_events_public from public;
grant select on public.host_events_public to anon, authenticated;


-- ═══════════════════════════════════════════════════════════════════
-- 2. THE ACTUAL LOCKDOWN — DO NOT RUN YET
-- ═══════════════════════════════════════════════════════════════════
-- Uncomment and run ONLY after every anon-key reader has been pointed at
-- host_events_public (see the report: nothing does today except a raw curl,
-- but the iOS build in flight has not been re-verified against it).
--
-- A column-level revoke here would be a no-op: Postgres consults the
-- table-level grant first and never looks at the column list. Since anon
-- needs NO column of this table once the view exists, the whole table grant
-- goes, rather than the revoke-then-grant-back dance greek_chapters needs.
--
--   revoke select on public.host_events from anon;
--
-- `authenticated` is deliberately left alone. BarPassHostEventRepository
-- .hostedEvents() reads `host_events?select=*,venues(name,slug)&host_id=eq.
-- <self>` with the user's own token, and both the `select=*` and the
-- `host_id=eq.` filter need SELECT on host_id. RESIDUAL, written down rather
-- than pretended away: a signed-in user can still enumerate the host_id of
-- published events. Signup is not an authorization boundary (venue_stories
-- .sql makes the same point about venue_media.user_id), so the clean finish
-- is to stop the client from filtering on host_id at all — serve the host's
-- own events from a `?mine=true` API route or a SECURITY DEFINER RPC that
-- uses auth.uid() internally — and only then revoke the table from
-- `authenticated` too. That is a client change, not this file.
--
-- Verify by behaviour after uncommenting, never by "the SQL ran":
--
--   do $$
--   begin
--     set local role anon;
--     begin
--       perform host_id from public.host_events limit 1;
--       raise exception 'FAIL: anon can still read host_events.host_id';
--     exception when insufficient_privilege then
--       raise notice 'OK: anon denied host_events';
--     end;
--     begin
--       perform id, title, starts_at from public.host_events_public limit 1;
--       raise notice 'OK: anon can still read the public listing view';
--     exception when insufficient_privilege then
--       raise exception 'FAIL: the public listing is broken for anon';
--     end;
--     reset role;
--   end $$;
