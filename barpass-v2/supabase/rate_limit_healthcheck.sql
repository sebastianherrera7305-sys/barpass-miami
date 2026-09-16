-- ─────────────────────────────────────────────────────────────────────────
-- OPERATIONAL FIX (audit 2026-09-16, finding #3 — medium):
-- the rate limiter fails OPEN, and failing open is invisible.
--
-- src/lib/rate-limit.ts returns `true` (allow) whenever the check_rate_limit
-- RPC errors. That is the right call — a broken rate limiter must not take
-- payments down with it — but it means a revoked EXECUTE grant, a renamed
-- function or a missing env var silently disables EVERY limit in production
-- while every endpoint keeps answering 200. Nothing looks broken. This has
-- already happened once, after the Phase 1 RPC lockdown migration, and the
-- only symptom was "public.rate_limits never gets any rows" — which nobody
-- sees unless they think to look at that table.
--
-- The console.error added in rate-limit.ts fixes the diagnosis. This file
-- fixes the DETECTION: something has to notice that the table went quiet.
--
-- Two independent signals, because they fail at different speeds:
--   (a) EXECUTE on check_rate_limit — catches the exact incident above the
--       moment the grant disappears, no waiting.
--   (b) freshness of public.rate_limits — catches everything else (wrong
--       env var, renamed function, code path removed, Vercel deploying a
--       build where checkRateLimit is never called), with a 24 h lag.
--
-- HONEST LIMIT, stated rather than smoothed over: signal (b) cannot tell
-- "the limiter is broken" apart from "nobody used a rate-limited route for
-- a day". At current traffic that distinction is real. It is still worth
-- alerting on, because the answer to both is the same — go look — and the
-- function reports WHICH signal tripped so the two are never confused.
--
-- Idempotent, safe to re-run. Run in the Supabase SQL editor.
-- ─────────────────────────────────────────────────────────────────────────


-- ═══════════════════════════════════════════════════════════════════
-- 1. THE ONE-SHOT QUERY — paste this any time you want the answer now
-- ═══════════════════════════════════════════════════════════════════
-- Returns exactly one row. `stale` is the alarm.
--
--   select
--     count(*)                                              as tracked_keys,
--     max(window_start)                                     as last_activity,
--     now() - max(window_start)                             as quiet_for,
--     (max(window_start) is null or max(window_start) < now() - interval '24 hours')
--                                                           as stale,
--     has_function_privilege('service_role',
--       'public.check_rate_limit(text,int,int)', 'execute') as rpc_executable
--   from public.rate_limits;


-- ═══════════════════════════════════════════════════════════════════
-- 2. THE SAME THING AS A FUNCTION, for cron and for the dashboard
-- ═══════════════════════════════════════════════════════════════════
-- SECURITY DEFINER because public.rate_limits has RLS on and no policies at
-- all (rate_limits_schema.sql) — by design, only the RPC touches it. EXECUTE
-- is granted to nobody but the owner; pg_cron runs as the job owner, and a
-- human runs it from the SQL editor as postgres.

create or replace function public.rate_limit_health()
returns table (
  healthy boolean,
  reason text,
  tracked_keys bigint,
  last_activity timestamptz,
  quiet_for interval,
  rpc_executable boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_keys bigint;
  v_last timestamptz;
  v_rpc boolean;
  v_stale boolean;
begin
  select count(*), max(window_start) into v_keys, v_last from public.rate_limits;

  -- to_regprocedure returns NULL instead of throwing when the function was
  -- dropped or renamed — itself one of the failures we are hunting. Check it
  -- before asking about privileges: has_function_privilege() on a missing
  -- oid raises, and an exception here would take the whole healthcheck down.
  -- CASE, not AND: SQL's AND is not guaranteed to short-circuit, and the
  -- whole point is to never hand a NULL oid to has_function_privilege.
  select case
           when to_regprocedure('public.check_rate_limit(text,int,int)') is null
             then false
           else has_function_privilege(
                  'service_role',
                  to_regprocedure('public.check_rate_limit(text,int,int)')::oid,
                  'execute'
                )
         end
    into v_rpc;
  v_rpc := coalesce(v_rpc, false);

  v_stale := v_last is null or v_last < now() - interval '24 hours';

  return query select
    (v_rpc and not v_stale),
    case
      when not v_rpc and v_stale then
        'service_role cannot EXECUTE check_rate_limit AND no rate-limit activity in 24h — the limiter is off'
      when not v_rpc then
        'service_role cannot EXECUTE check_rate_limit (dropped, renamed, or grant revoked) — every limit is failing open right now'
      when v_last is null then
        'public.rate_limits is empty — the limiter has never recorded a request'
      when v_stale then
        'no rate-limit activity in over 24h — either the limiter is failing open, or no rate-limited route was called'
      else
        'ok'
    end,
    v_keys, v_last, now() - v_last, v_rpc;
end;
$$;

revoke all on function public.rate_limit_health() from public, anon, authenticated;


-- ═══════════════════════════════════════════════════════════════════
-- 3. WHERE THE ALERT LANDS
-- ═══════════════════════════════════════════════════════════════════
-- Two places, both free:
--   · a row in public.ops_health_checks, so there is a history to look at
--     and the last result is one select away;
--   · a `raise warning`, which lands in the Supabase Postgres logs where a
--     log-based alert can be attached without any extra infrastructure.
-- No email/webhook dependency: the point of this file is that it cannot
-- itself fail silently for want of a third-party key.

create table if not exists public.ops_health_checks (
  id bigserial primary key,
  check_name text not null,
  healthy boolean not null,
  reason text not null,
  details jsonb,
  checked_at timestamptz not null default now()
);

alter table public.ops_health_checks enable row level security;
-- No policies: operational data, service role / SQL editor only. Same
-- convention as rate_limits and wallet_balances.

create index if not exists ops_health_checks_name_time_idx
  on public.ops_health_checks (check_name, checked_at desc);

create or replace function public.run_rate_limit_healthcheck()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  h record;
begin
  select * into h from public.rate_limit_health();

  insert into public.ops_health_checks (check_name, healthy, reason, details)
  values (
    'rate_limit',
    h.healthy,
    h.reason,
    jsonb_build_object(
      'tracked_keys', h.tracked_keys,
      'last_activity', h.last_activity,
      'quiet_for', h.quiet_for::text,
      'rpc_executable', h.rpc_executable
    )
  );

  if not h.healthy then
    raise warning '[healthcheck] rate_limit UNHEALTHY: %', h.reason;
  end if;
end;
$$;

revoke all on function public.run_rate_limit_healthcheck() from public, anon, authenticated;


-- ═══════════════════════════════════════════════════════════════════
-- 4. SCHEDULE IT — pg_cron, same pattern as grid_cron.sql
-- ═══════════════════════════════════════════════════════════════════
-- Hourly, not daily: the EXECUTE-grant signal is instant, and there is no
-- reason to sit on it for up to 24 hours. The 24 h threshold belongs to the
-- freshness signal, not to how often we look.

create extension if not exists pg_cron with schema cron;

-- Idempotent: unschedule first so re-running this file doesn't stack jobs.
select cron.unschedule('rate-limit-healthcheck')
where exists (select 1 from cron.job where jobname = 'rate-limit-healthcheck');

select cron.schedule(
  'rate-limit-healthcheck',
  '17 * * * *',
  $$ select public.run_rate_limit_healthcheck() $$
);


-- ═══════════════════════════════════════════════════════════════════
-- 5. VERIFY BY BEHAVIOUR
-- ═══════════════════════════════════════════════════════════════════
-- Run the check once by hand and read what it says — a scheduled job that
-- has never produced a row proves nothing:
--
--   select public.run_rate_limit_healthcheck();
--   select checked_at, healthy, reason, details
--   from public.ops_health_checks
--   where check_name = 'rate_limit'
--   order by checked_at desc limit 5;
--
-- And confirm the job is actually registered and running:
--
--   select jobname, schedule, active from cron.job where jobname = 'rate-limit-healthcheck';
--   select status, return_message, start_time
--   from cron.job_run_details
--   where jobid = (select jobid from cron.job where jobname = 'rate-limit-healthcheck')
--   order by start_time desc limit 5;
--
-- To prove the alarm can actually fire (rather than trusting that it would),
-- revoke the grant in a transaction, look, and roll back — never commit this:
--
--   begin;
--     revoke execute on function public.check_rate_limit(text,int,int) from service_role;
--     select healthy, reason from public.rate_limit_health();   -- expect healthy = false
--   rollback;
