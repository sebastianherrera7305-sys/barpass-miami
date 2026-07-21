-- SECURITY FIX (Pre-Launch Audit, Phase 1 #1): venues.validation_secret was
-- readable by ANY client. `venues` has `using (true)` for anon+authenticated
-- SELECT (schema.sql:48-51, needed so the app can list venues publicly) —
-- RLS is row-level, not column-level, so adding validation_secret to that
-- same table (venue_secrets_migration.sql / pending_migrations_combined.sql)
-- meant anyone calling the public Supabase REST API with the shipped anon
-- key could run `select validation_secret from venues` and get every
-- venue's door-staff secret — completely defeating /api/passes/redeem and
-- /api/venue/stats' entire auth model (fake redemptions, real-time revenue
-- snooping, impersonating any venue's staff).
--
-- Fix: move the secret to its own table with NO policies at all (default
-- deny for anon/authenticated; only the service role, which bypasses RLS,
-- can read it — same pattern already used correctly for wallet_balances
-- and rate_limits). Then drop the column from venues entirely, so even a
-- future accidental `using (true)` mistake on venues can't leak it again.
--
-- Safe to run regardless of which earlier script added the column —
-- every statement is idempotent (IF EXISTS / IF NOT EXISTS / ON CONFLICT).
-- Run once in the Supabase SQL editor.

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
