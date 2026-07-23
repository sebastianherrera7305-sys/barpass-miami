-- Account deletion (Apple Guideline 5.1.1(v)) — server-side support.
--
-- What Postgres handles automatically when auth.users row is deleted
-- (via existing FKs, no code needed):
--   CASCADE  → profiles, favorites, night_plans, wallet_balances,
--              wallet_transactions, and trips the user CREATED (creator_id)
--   SET NULL → orders.customer_id, passes.customer_id, venue_posts.user_id
--              (financial / venue audit trail preserved, just anonymized)
--
-- What Postgres does NOT handle: trips.member_ids / co_organizer_ids /
-- pending_requests are plain uuid[] with no FK, so a deleted user's id
-- would linger forever in other people's trips. This function strips it
-- from every trip where it appears as a non-creator. SECURITY DEFINER
-- because a normal user has no UPDATE policy on other people's trips.
--
-- Run once in the Supabase SQL editor.

create or replace function public.remove_user_from_all_trips(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.trips set
    member_ids       = array_remove(member_ids, p_user_id),
    co_organizer_ids = array_remove(co_organizer_ids, p_user_id),
    pending_requests = array_remove(pending_requests, p_user_id)
  where p_user_id = any(member_ids)
     or p_user_id = any(co_organizer_ids)
     or p_user_id = any(pending_requests);
end;
$$;

-- Server-only: only /api/account/delete (service role) calls this. Revoke
-- from anon/authenticated so it can't be invoked directly with the shipped
-- anon key — same lockdown pattern as adjust_wallet_balance / check_rate_limit.
revoke execute on function public.remove_user_from_all_trips(uuid) from public, anon, authenticated;
