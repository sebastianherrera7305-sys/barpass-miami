-- BarPass V2 — Passes (Skip the Line / Event Tickets / Table Reservations)
-- Server-side source of truth for the QR codes the iOS app displays. A pass
-- is only real once it exists here — door staff redeem against this table,
-- not against whatever string happens to be in the QR image (which anyone
-- could screenshot or fabricate without this check).

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

-- No insert/update/delete policy for anon/authenticated on purpose — only
-- the service role (server-side, via /api/passes and /api/passes/redeem)
-- may write. Issuing and redeeming both go through the API so quantity,
-- amount, and redemption state can never be forged from the client.
