-- BarPass V2 — Wallet balance
-- Kept in its own table (not on profiles) on purpose: profiles has a broad
-- "update own profile" policy for display_name/avatar_url, which would let
-- a client set their own balance directly via PATCH if it lived there.
-- wallet_balances has NO client write policy at all — every change goes
-- through adjust_wallet_balance(), called only by the service role from
-- /api/wallet/topup (after a real Stripe charge) and /api/wallet/spend.

create table if not exists public.wallet_balances (
  user_id uuid primary key references auth.users(id) on delete cascade,
  balance numeric not null default 0,
  updated_at timestamptz not null default now()
);

alter table public.wallet_balances enable row level security;

drop policy if exists "wallet balance readable by owner" on public.wallet_balances;
create policy "wallet balance readable by owner" on public.wallet_balances
  for select using (auth.uid() = user_id);

-- Atomic increment/decrement. Raises if it would go negative — callers
-- (the spend route) catch that and surface "insufficient_funds" rather
-- than ever letting balance dip below zero.
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
