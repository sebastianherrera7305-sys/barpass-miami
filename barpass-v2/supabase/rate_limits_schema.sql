-- Rate limiting para rutas de pago/canje — sin dependencia externa (Redis/
-- Upstash), reutiliza Supabase. Mismo patrón atómico que adjust_wallet_balance:
-- un upsert con lock de fila única, seguro bajo concurrencia.
--
-- Correr en el editor SQL de Supabase.

create table if not exists public.rate_limits (
  key text primary key,
  count int not null default 1,
  window_start timestamptz not null default now()
);

-- Nadie necesita leer/escribir esta tabla directo — solo la función RPC
-- (security definer) la toca. Sin policies = sin acceso vía anon/authenticated.
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
