-- Allows price_tier to honestly be "unknown" instead of defaulting to 2.
-- Confirmed live: price_tier is `smallint not null default 2 check
-- (price_tier between 1 and 4)` — the vast majority of venues never had a
-- real Google priceLevel and got silently defaulted to 2 (verified: 87% of
-- Miami, 66% of Austin). This makes NULL a legal, honest value so the app's
-- existing "N/D" display (PriceTier.symbol returns nil for .unknown) can
-- reflect reality instead of a fabricated default.
--
-- Idempotent, safe to re-run.

alter table public.venues alter column price_tier drop not null;
alter table public.venues alter column price_tier drop default;

alter table public.venues drop constraint if exists venues_price_tier_check;
alter table public.venues add constraint venues_price_tier_check
  check (price_tier is null or price_tier between 1 and 4);
