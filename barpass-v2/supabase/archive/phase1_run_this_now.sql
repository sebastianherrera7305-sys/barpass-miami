-- ============================================================
-- ⚠️  ARCHIVED — HISTORICAL DEPLOY SCRIPT. DO NOT RUN.
--
-- One-paste convenience script for the Phase 1 deploy, applied to
-- production on 2026-07-20 (commit 248b17a). Kept only as a record of
-- what was executed that day.
--
-- It is a CONCATENATION of migrations that already live in this
-- directory, so it necessarily replays history: it creates the V1
-- `adjust_wallet_balance` (line ~80), drops it (line ~139), then
-- creates the V2 that production runs today. Those duplicate
-- definitions are the reason this file was archived — the canonical
-- V2 lives in `../pass_payment_verification.sql`.
--
-- Re-running this against the live database would drop and recreate a
-- function production depends on, for no benefit.
-- ============================================================
--
-- Original header follows:
--
-- Phase 1 security fixes — run this ENTIRE file once, in the
-- Supabase SQL editor, in one paste. Order matters: it deploys
-- orders -> passes -> wallet (none of these exist in production
-- yet) -> the validation_secret lockdown -> the payment-verification
-- columns/RPC that reference the tables above.
--
-- Safe to run even if some pieces already partially exist —
-- every statement is idempotent (IF EXISTS / IF NOT EXISTS /
-- ON CONFLICT / CREATE OR REPLACE).
-- ============================================================

-- ---------- 1) orders_schema.sql ----------
create table if not exists public.orders (
  id text primary key,
  idempotency_key text unique,
  vendor_id text not null,
  customer_id uuid references auth.users(id) on delete set null,
  items jsonb not null,
  subtotal numeric not null,
  tax numeric not null,
  total numeric not null,
  payment_method text not null,
  stripe_payment_intent_id text,
  status text not null default 'completed',
  created_at timestamptz not null default now()
);

create index if not exists orders_customer_id_idx on public.orders (customer_id);
create index if not exists orders_vendor_id_idx on public.orders (vendor_id);

alter table public.orders enable row level security;

drop policy if exists "orders are readable by their owner" on public.orders;
create policy "orders are readable by their owner" on public.orders
  for select using (auth.uid() = customer_id);

-- ---------- 2) passes_schema.sql ----------
create table if not exists public.passes (
  id uuid primary key default gen_random_uuid(),
  pass_code text unique not null,
  kind text not null check (kind in ('skip_line', 'event_ticket', 'table')),
  venue_id text not null,
  venue_name text not null,
  customer_id uuid references auth.users(id) on delete set null,
  quantity int not null default 1,
  amount numeric not null,
  valid_until timestamptz not null,
  redeemed_at timestamptz,
  redeemed_by text,
  created_at timestamptz not null default now()
);

create index if not exists passes_venue_id_idx on public.passes (venue_id);
create index if not exists passes_pass_code_idx on public.passes (pass_code);

alter table public.passes enable row level security;

drop policy if exists "passes are readable by their owner" on public.passes;
create policy "passes are readable by their owner" on public.passes
  for select using (auth.uid() = customer_id);

-- ---------- 3) wallet_schema.sql ----------
create table if not exists public.wallet_balances (
  user_id uuid primary key references auth.users(id) on delete cascade,
  balance numeric not null default 0,
  updated_at timestamptz not null default now()
);

alter table public.wallet_balances enable row level security;

drop policy if exists "wallet balance readable by owner" on public.wallet_balances;
create policy "wallet balance readable by owner" on public.wallet_balances
  for select using (auth.uid() = user_id);

-- Superseded below by the version with p_kind + wallet_transactions ledger —
-- created here first only so "drop function if exists (uuid, numeric)"
-- in step 5 has something well-defined to drop if this is truly the
-- first-ever deploy. Harmless either way.
create or replace function public.adjust_wallet_balance(p_user_id uuid, p_amount numeric)
returns numeric
language plpgsql
security definer
set search_path = public
as $$
declare
  new_balance numeric;
begin
  insert into public.wallet_balances (user_id, balance, updated_at)
  values (p_user_id, p_amount, now())
  on conflict (user_id) do update
    set balance = wallet_balances.balance + excluded.balance,
        updated_at = now()
  returning balance into new_balance;

  if new_balance < 0 then
    raise exception 'insufficient_funds';
  end if;

  return new_balance;
end;
$$;

-- ---------- 4) venue_secrets_lockdown.sql ----------
create table if not exists public.venue_secrets (
  venue_id uuid primary key references public.venues(id) on delete cascade,
  validation_secret text not null
);

alter table public.venue_secrets enable row level security;
-- Deliberately no policies created — default-deny for anon/authenticated.

insert into public.venue_secrets (venue_id, validation_secret)
select id, validation_secret
from public.venues
where validation_secret is not null
on conflict (venue_id) do nothing;

alter table public.venues drop column if exists validation_secret;

-- ---------- 5) pass_payment_verification.sql ----------
create table if not exists public.wallet_transactions (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  amount     numeric not null,
  kind       text not null check (kind in ('topup', 'spend')),
  created_at timestamptz not null default now()
);

alter table public.wallet_transactions enable row level security;

drop policy if exists "wallet transactions readable by owner" on public.wallet_transactions;
create policy "wallet transactions readable by owner" on public.wallet_transactions
  for select using (auth.uid() = user_id);

create index if not exists wallet_transactions_user_idx
  on public.wallet_transactions (user_id, created_at desc);

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

alter table public.passes drop constraint if exists passes_has_payment_source;
alter table public.passes add constraint passes_has_payment_source check (
  (source_order_id is not null and source_wallet_transaction_id is null)
  or (source_order_id is null and source_wallet_transaction_id is not null)
) not valid;
