-- BarPass V2 — Orders (payments)
-- Written by the customer's own paid orders (Skip the Line, tables, drinks).
-- Rows are only ever inserted by /api/transactions using the service role key
-- (after Stripe confirms the charge) — never directly by the client.

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

-- No insert/update/delete policy for anon/authenticated roles on purpose —
-- only the service role (server-side, after a real Stripe charge) may write.
