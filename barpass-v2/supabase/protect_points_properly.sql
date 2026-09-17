-- Los puntos son escribibles desde el teléfono. Y el arreglo que había
-- escrito rompía los referidos.
--
-- Verificado por comportamiento el 2026-09-17: con la llave pública que
-- viaja dentro del binario de iOS, una cuenta nueva hizo PATCH de su propio
-- perfil con bpx_points = 999999 y quedó guardado. O sea que hoy cualquier
-- beneficio atado a puntos es regalable por cualquiera.
--
-- schema.sql ya define protect_profile_points() para esto, pero NO está
-- activo en producción — y es mejor que no lo haya estado, porque tal como
-- está escrito también revierte los premios legítimos: un trigger dispara
-- para TODA actualización, incluida la que hace qualify_and_reward_referral
-- (referrals_schema.sql) al sumar +200 al que invita. Activarlo así habría
-- apagado el programa de referidos en silencio, que es exactamente el
-- síntoma que alguien ya había reportado.
--
-- La distinción que faltaba es QUIÉN escribe:
--   · un cliente por PostgREST corre como `authenticated` o `anon`
--   · una función SECURITY DEFINER corre como su dueño (postgres)
-- Así que el trigger bloquea al primero y deja pasar al segundo. Los puntos
-- siguen siendo otorgables sólo por código del servidor, que es la regla que
-- ya cumple el saldo del wallet (adjust_wallet_balance).

-- SIN security definer, a propósito, y este es el detalle que hace que
-- funcione: un trigger DEFINER corre como su dueño, así que current_user
-- sería siempre postgres y la condición de abajo no se cumpliría nunca —
-- probado el 2026-09-17: con la versión definer, el ataque seguía pasando.
-- Como INVOKER, current_user es quien realmente escribe.
create or replace function public.protect_profile_points()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  -- current_user, no session_user: dentro de una función SECURITY DEFINER
  -- el primero es el dueño de la función y el segundo sigue siendo el
  -- usuario original. Mirar session_user bloquearía también los premios.
  if current_user in ('authenticated', 'anon')
     and new.bpx_points is distinct from old.bpx_points then
    new.bpx_points := old.bpx_points;
  end if;
  return new;
end;
$$;

drop trigger if exists protect_profile_points_trigger on public.profiles;
create trigger protect_profile_points_trigger
  before update on public.profiles
  for each row
  execute function public.protect_profile_points();

-- ═══════════════════════════════════════════════════════════════════
-- Verificación: desde AFUERA, nunca desde acá
-- ═══════════════════════════════════════════════════════════════════
-- La primera versión de este archivo traía un bloque `do $$` que se hacía
-- pasar por cliente con `set local role authenticated`. Daba OK sin probar
-- nada: en el editor SQL no hay JWT, así que auth.uid() es null, RLS bloquea
-- el update de prueba y el valor nunca cambia — el test pasaba por la razón
-- equivocada mientras el agujero seguía abierto.
--
-- La prueba real es con una cuenta descartable y la llave pública que viaja
-- dentro del binario de iOS, y tiene que cubrir tres casos:
--   1. PATCH directo de bpx_points            → debe quedar en 0
--   2. bpx_points colado junto a display_name → debe quedar en 0
--   3. premio del servidor (+200)             → DEBE entrar, o los
--      referidos quedan muertos sin que nada parezca roto
