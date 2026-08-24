-- Additive age-bracket tagging for venues, sourced from Kimi's per-city
-- research (see scripts/kimi-handoff/). Purely additive by design: a
-- low-rated venue that research recommends replacing is NEVER deleted or
-- edited here — it just doesn't get a bracket tag. A venue can carry
-- multiple brackets (a rooftop can pull both 25-35 and 35-50).
--
-- Idempotent, safe to re-run.

create table if not exists public.venue_age_brackets (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid references public.venues(id) on delete cascade not null,
  bracket text not null check (bracket in ('18_25', '25_35', '35_50')),
  why text not null,
  source text not null default 'kimi_research',
  created_at timestamptz not null default now(),
  unique(venue_id, bracket)
);

alter table public.venue_age_brackets enable row level security;

drop policy if exists "age brackets are public" on public.venue_age_brackets;
create policy "age brackets are public" on public.venue_age_brackets for select
  to anon, authenticated
  using (true);
-- No insert/update/delete policy — loaded only via service-role scripts
-- (scripts/kimi-handoff/load-age-brackets.ts), same convention as venues.
