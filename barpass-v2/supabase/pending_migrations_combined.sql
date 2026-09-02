-- ============================================================
-- Combina las 3 migraciones pendientes en un solo script:
-- 1) rate limiting (protege pagos/canje de abuso)
-- 2) secreto por venue (reemplaza el secreto único compartido)
-- 3) achicar fotos de venues (Google Places pedía 4800px)
-- Correr TODO junto, una sola vez, en el editor SQL de Supabase.
-- ============================================================

-- 1) Rate limiting
create table if not exists public.rate_limits (
  key text primary key,
  count int not null default 1,
  window_start timestamptz not null default now()
);

alter table public.rate_limits enable row level security;

create or replace function public.check_rate_limit(
  p_key text,
  p_max_requests int,
  p_window_seconds int
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int;
begin
  insert into public.rate_limits (key, count, window_start)
  values (p_key, 1, now())
  on conflict (key) do update set
    count = case
      when public.rate_limits.window_start < now() - (p_window_seconds || ' seconds')::interval
        then 1
      else public.rate_limits.count + 1
    end,
    window_start = case
      when public.rate_limits.window_start < now() - (p_window_seconds || ' seconds')::interval
        then now()
      else public.rate_limits.window_start
    end
  returning count into v_count;

  return v_count <= p_max_requests;
end;
$$;

-- 2) Secreto por venue
-- ⚠️ HISTORICAL — SUPERSEDED. DO NOT RUN ON A LIVE DATABASE.
-- This put validation_secret directly on `venues`, which has a public
-- `using (true)` SELECT policy (schema.sql) — RLS is row-level, not
-- column-level, so this let anyone with the shipped anon key read every
-- venue's door-staff secret via `select validation_secret from venues`.
-- Superseded by venue_secrets_lockdown.sql, which moves the secret to its
-- own zero-policy `venue_secrets` table instead. See that file for the
-- real migration; the block that used to be here has been removed so a
-- run-everything-in-this-file mistake can't reintroduce the leak.

-- 3) Achicar fotos de venues (4800px -> 1200px)
update public.venues
set image_url = regexp_replace(image_url, '=s\d+-w\d+$', '=s1200-w600')
where image_url like '%googleusercontent.com%=s%-w%';
