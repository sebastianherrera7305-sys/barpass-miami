-- Pass registration idempotency (2026-09-12)
--
-- Context: after a card / Apple Pay / Wallet payment the iOS app calls
-- POST /api/passes to mint the pass its QR code points at. On bad LTE inside
-- a venue that call used to be fire-and-forget: the user was charged, the
-- server never recorded the pass, and the door turned them away. The app
-- now keeps a durable outbox and RE-SENDS the same registration (same
-- pass_code, same order id / wallet transaction id) until the server
-- answers, so the server must give the same answer every time for the same
-- payment. That relies on exactly one pass existing per payment source.
--
-- Both unique indexes were introduced in pass_payment_verification.sql.
-- This file re-asserts them in an idempotent form (safe to paste even if
-- that migration already ran — `if not exists` makes each statement a
-- no-op when the object is already there), and adds nothing else: the
-- route derives the pass from the payment, so no new column is needed.
-- Run once in the Supabase SQL editor.

-- Every pass points at exactly one verified payment. The columns exist
-- since pass_payment_verification.sql; harmless if already present.
alter table public.passes add column if not exists source_order_id text
  references public.orders(id);
alter table public.passes add column if not exists source_wallet_transaction_id uuid
  references public.wallet_transactions(id);

-- One pass per Stripe-backed order. POST /api/passes looks a retry up by
-- (source_order_id, customer_id) before inserting and returns the existing
-- pass; this index is what makes that lookup authoritative under a race of
-- two simultaneous retries.
create unique index if not exists passes_source_order_id_unique
  on public.passes (source_order_id)
  where source_order_id is not null;

-- Same guarantee for a BarPass Wallet debit.
create unique index if not exists passes_source_wallet_txn_unique
  on public.passes (source_wallet_transaction_id)
  where source_wallet_transaction_id is not null;

-- The retry lookup and the owner-scoped pass_code lookup both filter on
-- customer_id; the table has no index on it yet (only venue_id and
-- pass_code). Cheap, and keeps /api/passes fast as the table grows.
create index if not exists passes_customer_id_idx
  on public.passes (customer_id);

-- Sanity check (read-only): if this returns any row, two passes share one
-- payment and the unique index above could NOT have been created — fix
-- the duplicates first, then re-run this file.
--   select source_order_id, count(*) from public.passes
--     where source_order_id is not null
--     group by source_order_id having count(*) > 1;
