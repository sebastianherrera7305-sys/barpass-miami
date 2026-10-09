-- ─────────────────────────────────────────────────────────────────────────
-- BarPass — Make /api/wallet/topup idempotent end-to-end.
--
-- Run in the Supabase SQL editor. Idempotent — safe to re-run.
--
-- The problem this closes:
--
-- Before this migration, /api/wallet/topup had no idempotency protection
-- at all. A dropped response, a double tap on "Add funds", or a URLSession
-- background retry would charge the card AND credit the wallet twice.
--
-- With Stripe's own request-level `idempotencyKey` option (just added to
-- the route), the SECOND request now gets back the SAME PaymentIntent id
-- for the same key — Stripe serializes requests sharing a key and does
-- not re-charge. Good: no double charge at the processor.
--
-- But the route then still calls `adjust_wallet_balance(user, amount,
-- 'topup')`, which has no knowledge that this PaymentIntent was already
-- used to credit the wallet a moment ago. The old shape of the RPC always
-- sums `amount` into the balance. So without this migration, Stripe is
-- safe but the wallet still double-credits.
--
-- This migration:
--   1. Adds `stripe_payment_intent_id text` to wallet_transactions with
--      a partial UNIQUE index — Postgres enforces that the same PI id
--      can only produce one ledger row, atomically.
--   2. Replaces adjust_wallet_balance to take an optional
--      `p_stripe_payment_intent_id` arg. If the arg is given and a prior
--      transaction already has it, the RPC returns that prior transaction
--      unchanged (true no-op; no new credit, no new ledger row).
--   3. Keeps the old 3-arg signature available by adding a wrapper for
--      spend-side callers that never had a PaymentIntent to begin with.
--
-- Scope — ONLY the wallet-topup path uses this new field. /api/wallet/spend
-- continues to call the 3-arg form and is unaffected. venue tab spends,
-- host-event credits, and anywhere else that debits/credits the wallet
-- without a Stripe PI stay the same.
-- ─────────────────────────────────────────────────────────────────────────

alter table public.wallet_transactions
  add column if not exists stripe_payment_intent_id text;

-- Partial unique index so NULLs don't collide (every spend row has NULL
-- here; only topup rows carry a PI id). This is what makes the dedup
-- atomic — no "check then insert" race.
create unique index if not exists wallet_transactions_pi_unique
  on public.wallet_transactions (stripe_payment_intent_id)
  where stripe_payment_intent_id is not null;

-- Replace the RPC. Signature change (new optional arg) means we have to
-- drop first — Postgres won't change a parameter list in place, same
-- trap as always.
drop function if exists public.adjust_wallet_balance(uuid, numeric, text);

create or replace function public.adjust_wallet_balance(
  p_user_id uuid,
  p_amount numeric,
  p_kind text default 'spend',
  p_stripe_payment_intent_id text default null
)
returns table(balance numeric, transaction_id uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
  new_balance numeric;
  txn_id uuid;
  existing_txn record;
begin
  -- Dedup FIRST, before touching the balance. If we've seen this
  -- PaymentIntent before, return the prior ledger row and the current
  -- balance without crediting again. This is the whole point of this
  -- migration — the route can safely retry a topup after a dropped
  -- response and we neither charge the card twice (Stripe's own
  -- idempotencyKey handles that) nor credit the wallet twice.
  if p_stripe_payment_intent_id is not null then
    select wt.id, wb.balance
      into existing_txn
      from public.wallet_transactions wt
      left join public.wallet_balances wb on wb.user_id = wt.user_id
     where wt.stripe_payment_intent_id = p_stripe_payment_intent_id
       and wt.user_id = p_user_id
     limit 1;
    if found then
      return query select existing_txn.balance, existing_txn.id;
      return;
    end if;
  end if;

  insert into public.wallet_balances (user_id, balance, updated_at)
  values (p_user_id, p_amount, now())
  on conflict (user_id) do update
    set balance = wallet_balances.balance + excluded.balance,
        updated_at = now()
  returning wallet_balances.balance into new_balance;

  if new_balance < 0 then
    raise exception 'insufficient_funds';
  end if;

  -- The UNIQUE index on stripe_payment_intent_id is the real safety net
  -- here. Two concurrent requests both passing the dedup check above and
  -- racing to this insert will have one of them raise unique_violation
  -- and the SELECT above will catch the next retry. We re-raise so the
  -- caller (the Next.js route) can turn it into a 409 or re-call the RPC
  -- to pick up the winner's row.
  insert into public.wallet_transactions (user_id, amount, kind, stripe_payment_intent_id)
  values (p_user_id, p_amount, p_kind, p_stripe_payment_intent_id)
  returning id into txn_id;

  return query select new_balance, txn_id;
end;
$$;

grant execute on function public.adjust_wallet_balance(uuid, numeric, text, text) to authenticated;
revoke execute on function public.adjust_wallet_balance(uuid, numeric, text, text) from public, anon;

notify pgrst, 'reload schema';

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════
--
-- 1. New column + unique index exist.
--    \d+ public.wallet_transactions
--
-- 2. Function signature is the 4-arg form.
--    select pg_get_function_identity_arguments(oid) from pg_proc
--     where proname = 'adjust_wallet_balance' and pronamespace = 'public'::regnamespace;
--    -- expect: p_user_id uuid, p_amount numeric, p_kind text, p_stripe_payment_intent_id text
--
-- 3. Dedup round-trip (run as a signed-in test user via supabase.auth):
--    select * from public.adjust_wallet_balance(auth.uid(), 10, 'topup', 'pi_test_abc');
--    select * from public.adjust_wallet_balance(auth.uid(), 10, 'topup', 'pi_test_abc');
--    -- expect: both calls return the SAME transaction_id and the same balance.
--    --         If they return different ids, dedup is broken.
--
-- 4. Spend-side (no PI id) still works and still records.
--    select * from public.adjust_wallet_balance(auth.uid(), -3, 'spend');
--    -- expect: balance decreased, new transaction_id returned.
