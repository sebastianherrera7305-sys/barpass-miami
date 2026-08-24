-- Real, crowdsourced "what age was the crowd" signal — collected at
-- check-out (the one moment we actually know someone was there and is now
-- leaving, since there's no geofencing). Combines with venue_age_brackets
-- (Kimi's static research) rather than replacing it: real reports only
-- take over once there are enough of them to mean something (3+ for a
-- bracket), otherwise the research tag is what the app shows.
--
-- Idempotent, safe to re-run.

create table if not exists public.venue_age_reports (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid references public.venues(id) not null,
  user_id uuid references public.profiles(id) not null,
  bracket text not null check (bracket in ('18_25', '25_35', '35_50')),
  created_at timestamptz not null default now(),
  -- A separate date column so "one report per user per venue per day" is a
  -- real constraint — unique(..., created_at) alone never fires, since
  -- created_at's microsecond precision makes two rows collide on it
  -- essentially never, regardless of same-day intent.
  report_date date not null default current_date,
  unique (venue_id, user_id, report_date)
);

alter table public.venue_age_reports enable row level security;

drop policy if exists "age reports are public" on public.venue_age_reports;
create policy "age reports are public" on public.venue_age_reports for select
  to anon, authenticated
  using (true);

drop policy if exists "report own perceived age" on public.venue_age_reports;
create policy "report own perceived age" on public.venue_age_reports for insert
  to authenticated
  with check (user_id = auth.uid());
-- No update/delete policy — a report is a point-in-time observation, not
-- something to edit after the fact.

create index if not exists venue_age_reports_venue_idx on public.venue_age_reports (venue_id);

-- The "effective" bracket set the app should show, per (venue, bracket)
-- pair: real reports win for that specific bracket once there are 3+ of
-- them; otherwise whatever venue_age_brackets (Kimi research) says for
-- that bracket is used. Matched per-bracket, not per-venue overall — a
-- venue can have "18_25" confirmed by real reports while "25_35" still
-- shows the research tag.
create or replace view public.venue_age_effective as
with real_brackets as (
  select venue_id, bracket, count(*) as report_count
  from venue_age_reports
  group by venue_id, bracket
  having count(*) >= 3
),
all_brackets as (
  select venue_id, bracket from real_brackets
  union
  select venue_id, bracket from venue_age_brackets
)
select
  ab.venue_id,
  ab.bracket,
  case when rb.bracket is not null then 'user_reports' else 'kimi_research' end as source,
  rb.report_count
from all_brackets ab
left join real_brackets rb on rb.venue_id = ab.venue_id and rb.bracket = ab.bracket;
