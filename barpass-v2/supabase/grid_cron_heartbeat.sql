-- The Grid's refresh_grid_pulses() runs via pg_cron every 5 minutes (see
-- grid_cron.sql) with zero observability if it ever silently stops — the
-- extension gets disabled, a migration wipes the job, the project pauses
-- and resumes without it, whatever. grid_pulses itself can't tell you: an
-- empty table is indistinguishable from "nobody's checked into anywhere
-- right now" (a completely normal state at 4pm) vs. "this hasn't run in
-- three days." A heartbeat the function updates on every single run,
-- whether or not it found any active check-ins, fixes that.
--
-- Idempotent, safe to re-run.

create table if not exists public.cron_heartbeats (
  job_name text primary key,
  last_run_at timestamptz not null
);

alter table public.cron_heartbeats enable row level security;

-- Read-only, and only for authenticated staff-facing tooling (the health
-- check script below uses the service role key, which bypasses RLS
-- anyway) — no anon policy at all, this has no reason to be public.
drop policy if exists "authenticated can read heartbeats" on public.cron_heartbeats;
create policy "authenticated can read heartbeats" on public.cron_heartbeats for select
  to authenticated
  using (true);
-- No insert/update/delete policy for anon/authenticated — only
-- refresh_grid_pulses() (security definer) writes this.

create or replace function public.refresh_grid_pulses() returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into cron_heartbeats (job_name, last_run_at) values ('refresh-grid-pulses', now())
    on conflict (job_name) do update set last_run_at = excluded.last_run_at;

  delete from grid_pulses where expires_at < now();
  insert into grid_pulses (venue_id, lat, lng, pulse_count, age_18_20_count, age_21_plus_count, last_updated, expires_at)
  select
    v.id, v.lat, v.lng,
    count(distinct c.user_id),
    count(distinct c.user_id) filter (where c.age_at_checkin between 18 and 20),
    count(distinct c.user_id) filter (where c.age_at_checkin >= 21),
    now(), now() + interval '45 minutes'
  from venues v
  join venue_checkins c on c.venue_id = v.id
  where c.checked_in_at > now() - interval '30 minutes'
    and (c.checked_out_at is null or c.checked_out_at > now() - interval '30 minutes')
  group by v.id, v.lat, v.lng
  on conflict (venue_id) do update set
    lat = excluded.lat, lng = excluded.lng,
    pulse_count = excluded.pulse_count,
    age_18_20_count = excluded.age_18_20_count,
    age_21_plus_count = excluded.age_21_plus_count,
    last_updated = excluded.last_updated,
    expires_at = excluded.expires_at;
end;
$$;

-- Verify after running: select * from cron_heartbeats;
-- Then check staleness anytime with: npm run check:grid-health
