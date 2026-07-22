-- SECURITY FIX (Phase 1 post-migration verification, take 2): the first
-- pass of this fix revoked EXECUTE from PUBLIC only, and testing proved
-- that did NOT actually block anon — Supabase applies its own default
-- privilege rule (`alter default privileges in schema public grant
-- execute on functions to anon, authenticated`) at function-creation
-- time, which is a SEPARATE, EXPLICIT grant to those two roles, not
-- something that flows from PUBLIC membership. Revoking from PUBLIC left
-- that explicit grant untouched, so anon could still call
-- adjust_wallet_balance, check_rate_limit, and redeem_trip_invite exactly
-- as before — confirmed live (anon POSTs to all three RPCs after the
-- first "fix" still executed the function body).
--
-- This version revokes from anon AND authenticated explicitly (not just
-- PUBLIC), then re-grants authenticated back only on redeem_trip_invite,
-- which is the one function real logged-in users are meant to call
-- directly. Loops over every overload of each name instead of assuming
-- exactly one, so a lingering old signature can't hide from the fix.
--
-- Idempotent, safe to re-run, no-ops on any function that doesn't exist
-- in this environment.

do $$
declare
  r record;
begin
  for r in
    select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in ('adjust_wallet_balance', 'check_rate_limit')
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', r.oid::regprocedure);
  end loop;

  for r in
    select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'redeem_trip_invite'
  loop
    execute format('revoke execute on function %s from public, anon', r.oid::regprocedure);
    execute format('grant execute on function %s to authenticated', r.oid::regprocedure);
  end loop;

  for r in
    select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in ('handle_new_user', 'protect_profile_points')
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', r.oid::regprocedure);
  end loop;
end $$;
