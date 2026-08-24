-- Allows avg_spend to honestly be "unknown" instead of a fake 0.
-- Confirmed live: 1,642 of 1,817 venues (90%) carry avg_spend = 0 as a
-- hardcoded placeholder from add-venues.ts, not a real "$0 average spend"
-- fact. Mirrors price_tier_allow_null.sql's fix for the exact same class
-- of bug.
--
-- Idempotent, safe to re-run.

alter table public.venues alter column avg_spend drop not null;
alter table public.venues alter column avg_spend drop default;
