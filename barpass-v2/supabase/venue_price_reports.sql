-- Real, crowdsourced drink prices — "lo que se necesita es saber qué tragos
-- venden y a cuánto" (2026-09-08). Venue websites publish prices for only a
-- minority of venues (Miami: ~1 in 5), so the scalable source is the person
-- who just paid: asked at check-out, one tap, same moment as the age
-- report. Aggregated as a median so one wrong tap can't move the number,
-- and shown only once there are 3+ reports (venue_price_stats).
--
-- Idempotent, safe to re-run.

create table if not exists public.venue_price_reports (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid references public.venues(id) not null,
  user_id uuid references public.profiles(id) not null,
  -- What one drink cost, in cents. Bounded to keep a fat-finger $1 or
  -- $9,999 from ever entering the median.
  drink_price_cents int not null check (drink_price_cents between 300 and 30000),
  created_at timestamptz not null default now(),
  report_date date not null default current_date,
  unique (venue_id, user_id, report_date)
);

alter table public.venue_price_reports enable row level security;

drop policy if exists "price reports are public" on public.venue_price_reports;
create policy "price reports are public" on public.venue_price_reports for select
  to anon, authenticated
  using (true);

drop policy if exists "report own drink price" on public.venue_price_reports;
create policy "report own drink price" on public.venue_price_reports for insert
  to authenticated
  with check (user_id = auth.uid());
-- No update/delete: a report is a point-in-time observation.

create index if not exists venue_price_reports_venue_idx on public.venue_price_reports (venue_id);

-- Per-venue median drink price, last 180 days, only with 3+ reports.
create or replace view public.venue_price_stats
with (security_invoker = true) as
select
  venue_id,
  (percentile_cont(0.5) within group (order by drink_price_cents))::int as median_drink_cents,
  count(*)::int as report_count,
  max(created_at) as last_report_at
from venue_price_reports
where created_at > now() - interval '180 days'
group by venue_id
having count(*) >= 3;
