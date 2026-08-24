-- SECURITY FIX (Pre-Launch Audit, Phase 1 #2): POST /api/passes accepted a
-- client-supplied `amount`/`quantity` and inserted a `passes` row with no
-- server-side link to a real payment — a modified client could POST
-- directly with a fabricated amount and receive a valid, redeemable QR
-- pass without ever paying. Fix: every pass must now reference a real,
-- previously-verified payment (a Stripe-backed `orders` row, or a real
-- BarPass Wallet debit) — the API route derives `amount` from that source
-- server-side instead of trusting the client, and a unique constraint
-- guarantees the same payment can never back two passes (blocks replay).
--
-- Run once in the Supabase SQL editor, after venue_secrets_lockdown.sql.

-- Wallet debit ledger — /api/wallet/spend previously only returned the new
-- balance, with no record a later request could reference to prove "this
-- specific debit happened". adjust_wallet_balance() below is updated to
-- write one row per balance change and return its id alongside the balance.
create table if not exists public.wallet_transactions (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  amount     numeric not null, -- negative = spend, positive = top-up
  kind       text not null check (kind in ('topup', 'spend')),
  created_at timestamptz not null default now()
);

alter table public.wallet_transactions enable row level security;

drop policy if exists "wallet transactions readable by owner" on public.wallet_transactions;
create policy "wallet transactions readable by owner" on public.wallet_transactions
  for select using (auth.uid() = user_id);
-- No insert/update/delete policy for anon/authenticated — only the
-- service role (via adjust_wallet_balance, security definer) writes.

create index if not exists wallet_transactions_user_idx
  on public.wallet_transactions (user_id, created_at desc);

-- ============================================================
-- ✅ CANONICAL / AUTHORITATIVE DEFINITION of adjust_wallet_balance.
--
-- This is the version production runs. Any other copy in this repo is
-- historical: V1 in `wallet_schema.sql` (superseded) and the archived
-- one-paste script in `archive/phase1_run_this_now.sql`. Change the
-- wallet RPC HERE and nowhere else.
--
--   signature   : (p_user_id uuid, p_amount numeric,
--                  p_kind text default 'spend')
--   returns     : table(balance numeric, transaction_id uuid) — callers
--                 read `rpcData[0]`, so this is not interchangeable with
--                 V1's bare numeric return
--   p_kind      : labels the movement ('topup' | 'spend') in the ledger
--   side effect : inserts one row into `wallet_transactions`, which is
--                 what lets a pass reference a verified payment
--   security    : SECURITY DEFINER with `search_path = public` pinned —
--                 the pinning is what stops the classic privilege
--                 escalation against definer functions
--   safety      : raises `insufficient_funds` before committing if the
--                 resulting balance would go negative
-- ============================================================
--
-- Return type changes (numeric -> table), so the old function must be
-- dropped first — Postgres won't let you change a return type in place.
drop function if exists public.adjust_wallet_balance(uuid, numeric);

create or replace function public.adjust_wallet_balance(
  p_user_id uuid,
  p_amount numeric,
  p_kind text default 'spend'
)
returns table(balance numeric, transaction_id uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
  new_balance numeric;
  txn_id uuid;
begin
  insert into public.wallet_balances (user_id, balance, updated_at)
  values (p_user_id, p_amount, now())
  on conflict (user_id) do update
    set balance = wallet_balances.balance + excluded.balance,
        updated_at = now()
  returning wallet_balances.balance into new_balance;

  if new_balance < 0 then
    raise exception 'insufficient_funds';
  end if;

  insert into public.wallet_transactions (user_id, amount, kind)
  values (p_user_id, p_amount, p_kind)
  returning id into txn_id;

  return query select new_balance, txn_id;
end;
$$;

-- Passes must reference exactly one verified payment source. Both
-- reference columns carry a UNIQUE constraint, so the same order or wallet
-- debit can never be reused to mint a second pass (Postgres enforces this
-- atomically — it's the real safety net against a race of two simultaneous
-- requests reusing one payment, not just an application-level check).
alter table public.passes add column if not exists source_order_id text
  references public.orders(id);
alter table public.passes add column if not exists source_wallet_transaction_id uuid
  references public.wallet_transactions(id);

drop index if exists passes_source_order_id_unique;
create unique index passes_source_order_id_unique
  on public.passes (source_order_id) where source_order_id is not null;

drop index if exists passes_source_wallet_txn_unique;
create unique index passes_source_wallet_txn_unique
  on public.passes (source_wallet_transaction_id) where source_wallet_transaction_id is not null;

-- NOT VALID: passes created before this migration have neither column set
-- and can't be retroactively linked to a payment we didn't record a
-- reference for. This enforces the rule for every new row going forward
-- without requiring a backfill of historical data we don't have.
alter table public.passes drop constraint if exists passes_has_payment_source;
alter table public.passes add constraint passes_has_payment_source check (
  (source_order_id is not null and source_wallet_transaction_id is null)
  or (source_order_id is null and source_wallet_transaction_id is not null)
) not valid;
