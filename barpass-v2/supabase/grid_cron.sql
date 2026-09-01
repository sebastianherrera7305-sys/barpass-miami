-- The Grid: refresh grid_pulses every 5 minutes.
--
-- This used to be a Vercel Cron (vercel.json, */5 * * * *), but Vercel's
-- Hobby plan only allows once-daily crons and REJECTS THE WHOLE DEPLOY
-- when it sees a more frequent expression — every push since 2026-08-23
-- failed at deploy creation because of it.
--
-- pg_cron is the better home for it anyway: refresh_grid_pulses is already
-- a Postgres function, so scheduling it in the database skips the HTTP
-- round trip, needs no CRON_SECRET, and costs nothing on Supabase's free
-- tier. Run this once in the Supabase SQL editor.

create extension if not exists pg_cron with schema cron;

-- Idempotent: unschedule first so re-running this file doesn't stack jobs.
select cron.unschedule('refresh-grid-pulses')
where exists (select 1 from cron.job where jobname = 'refresh-grid-pulses');

select cron.schedule(
  'refresh-grid-pulses',
  '*/5 * * * *',
  $$ select public.refresh_grid_pulses() $$
);

-- Verify:  select jobname, schedule, active from cron.job;
