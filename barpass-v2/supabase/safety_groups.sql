-- ═══════════════════════════════════════════════════════════════════════
-- SAFETY GROUPS — grupo efímero, chat efímero, "buscar al líder" con
-- apretón de manos UWB, y enlaces mágicos
--
-- Run in the Supabase SQL editor, AFTER: schema.sql, trips_schema.sql,
-- friend_graph_schema.sql (bp_blocked_between), rate_limits_schema.sql and
-- safety_beacon.sql. Idempotent — safe to re-run. Does not touch
-- safety_beacon.sql's tables.
--
-- QUÉ ES
-- ---------------------------------------------------------------------
-- Un GRUPO EFÍMERO es un círculo chico (máx. 12) con cuenta regresiva:
-- alguien lo crea y es el LÍDER, la gente entra (con un enlace mágico
-- barpass://group?id=... o con un código de 6 caracteres) y a las N horas
-- (default 4, tope 12) todo desaparece — miembros, mensajes y búsquedas.
-- El líder puede cerrar el evento antes (end_safety_group).
--
--   · CHAT EFÍMERO: mensajes cifrados en reposo (vault + pgp_sym), 1-500
--     caracteres, 20 por minuto, borrados con el grupo.
--   · BUSCAR AL LÍDER (la máquina de estados):
--       A. Un miembro toca "Buscar al líder" → seek_group_leader().
--       B. El servidor manda un push time-sensitive SÓLO al líder
--          (/api/safety/notify, get_seek_push_targets).
--       C. El líder toca el push, la app abre en primer plano y los DOS
--          teléfonos arrancan NISession. Los tokens de descubrimiento
--          cruzan por publish_seek_token / get_seek_tokens.
--       D. A menos de 9 m (30 ft), el teléfono del líder vibra fuerte y
--          muestra un banner local. Todo eso es cliente: el servidor no
--          sabe la distancia y no la recibe.
--       E. El líder toca el banner → authorize_rally_point() → punto de encuentro.
--   · SÓLO EL LÍDER PUEDE ENCENDER EL PUNTO DE ENCUENTRO. authorize_rally_point()
--     rechaza con not_target a cualquiera que no sea el objetivo de esa
--     búsqueda. Es la segunda llave: la primera es que la pantalla del
--     buscador no tiene ese botón.
--   · TOKENS DE PUSH: una tabla de dispositivos.
--
-- LO QUE NO GUARDA, A PROPÓSITO
-- ---------------------------------------------------------------------
-- Ninguna coordenada — ni GPS, ni distancia, ni dirección — en ninguna
-- tabla, ni en los mensajes, ni en los pushes. El token de descubrimiento
-- de NearbyInteraction es un blob opaco que no lleva posición y no sirve
-- fuera de la sesión que lo generó. Rastrear personas por el servidor es un
-- cambio de privacidad que safety_beacon.sql rechaza y este archivo no
-- revierte.
--
-- QUIÉN ENTRA
-- ---------------------------------------------------------------------
-- Con el enlace o el código. Un enlace reenviado o posteado lo puede usar
-- cualquiera, así que tres frenos: tope de 12 personas, NADIE bloqueado (en
-- ninguna dirección) por un miembro actual puede entrar, y el líder puede
-- sacar gente y cerrar el evento. El id del grupo es un UUID: no se puede
-- adivinar, y aun así join_* cuenta cada intento contra un límite.
--
-- pgcrypto vive en `extensions`, no en `public` (fix_pgcrypto_search_path
-- .sql): toda función que cifra va con search_path = public, extensions.
-- ═══════════════════════════════════════════════════════════════════════

create extension if not exists pgcrypto with schema extensions;
create extension if not exists supabase_vault cascade;


-- ══════════════════════════════════════════════════════════════════
-- 1. TABLAS
-- ══════════════════════════════════════════════════════════════════

-- Tokens de APNs. Un usuario puede tener varios teléfonos; un token
-- pertenece a UN usuario a la vez (si alguien inicia sesión en un
-- teléfono que era de otra cuenta, el token cambia de dueño).
create table if not exists public.device_tokens (
  token       text primary key check (char_length(token) between 32 and 200),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  platform    text not null default 'ios' check (platform = 'ios'),
  environment text not null check (environment in ('sandbox', 'production')),
  updated_at  timestamptz not null default now()
);
create index if not exists device_tokens_user_idx on public.device_tokens (user_id);

create table if not exists public.safety_groups (
  id          uuid primary key default gen_random_uuid(),
  code        text not null,
  created_by  uuid not null references public.profiles(id) on delete cascade,
  trip_id     uuid references public.trips(id) on delete set null,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null,
  ended_at    timestamptz,
  constraint safety_groups_ttl check (expires_at > created_at
                                      and expires_at <= created_at + interval '12 hours 1 minute')
);
-- El código es único ENTRE grupos vivos; uno vencido lo libera.
create unique index if not exists safety_groups_live_code_idx
  on public.safety_groups (code) where ended_at is null;
create index if not exists safety_groups_expires_idx on public.safety_groups (expires_at);

create table if not exists public.safety_group_members (
  group_id  uuid not null references public.safety_groups(id) on delete cascade,
  user_id   uuid not null references public.profiles(id) on delete cascade,
  role      text not null default 'member' check (role in ('leader', 'member')),
  joined_at timestamptz not null default now(),
  left_at   timestamptz,
  -- EXPULSADO ≠ "SE FUE". `left_at` dice que la persona ya no está; estas dos
  -- dicen POR QUÉ. Sacar a alguien pone las dos; irse por voluntad propia no
  -- las toca, y esa persona puede volver. Sin esta distinción el expulsado
  -- entra otra vez con el mismo enlace o el mismo código, y el líder sólo
  -- puede volver a sacarlo, en loop.
  removed_by uuid references public.profiles(id) on delete set null,
  removed_at timestamptz,
  primary key (group_id, user_id)
);
-- Bases donde una versión anterior de este archivo ya creó la tabla.
alter table public.safety_group_members
  add column if not exists removed_by uuid references public.profiles(id) on delete set null,
  add column if not exists removed_at timestamptz;
-- "¿En qué grupo vivo estoy?" — la pregunta más frecuente.
create index if not exists safety_group_members_user_idx
  on public.safety_group_members (user_id) where left_at is null;

create table if not exists public.safety_group_messages (
  id         uuid primary key default gen_random_uuid(),
  group_id   uuid not null references public.safety_groups(id) on delete cascade,
  sender_id  uuid not null references public.profiles(id) on delete cascade,
  text_enc   bytea not null,
  created_at timestamptz not null default now()
);
create index if not exists safety_group_messages_group_idx
  on public.safety_group_messages (group_id, created_at);

-- Una búsqueda: `seeker_id` busca a `target_id`, que es el líder EN ESE
-- MOMENTO. Vive 20 minutos. Sólo el target puede encender el punto de encuentro.
create table if not exists public.safety_group_seeks (
  id         uuid primary key default gen_random_uuid(),
  group_id   uuid not null references public.safety_groups(id) on delete cascade,
  seeker_id  uuid not null references public.profiles(id) on delete cascade,
  target_id  uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '20 minutes',
  ended_at   timestamptz,
  lit_at     timestamptz,
  constraint safety_group_seeks_distinct check (seeker_id <> target_id)
);

-- Una versión anterior de este archivo llamaba `ignited_at` a esta columna (cuando
-- la luz del líder se llamaba "faro"). Si ya se corrió, se renombra en el lugar:
-- no se pierde ningún dato y volver a correr el archivo sigue siendo seguro.
do $$
begin
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'safety_group_seeks'
                and column_name = 'ignited_at')
     and not exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'safety_group_seeks'
                and column_name = 'lit_at') then
    alter table public.safety_group_seeks rename column ignited_at to lit_at;
  end if;
end $$;
create index if not exists safety_group_seeks_group_idx
  on public.safety_group_seeks (group_id, created_at desc);
create index if not exists safety_group_seeks_seeker_live_idx
  on public.safety_group_seeks (seeker_id) where ended_at is null;
create index if not exists safety_group_seeks_target_live_idx
  on public.safety_group_seeks (target_id) where ended_at is null;

-- El buzón donde los dos teléfonos se pasan el token de NearbyInteraction.
-- Es un blob opaco: no lleva ubicación y no significa nada fuera de la
-- NISession que lo generó. `can_range = false` es un dato, no un silencio:
-- "mi teléfono no tiene UWB", para que el otro deje de esperar un token.
create table if not exists public.safety_group_seek_tokens (
  seek_id    uuid not null references public.safety_group_seeks(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  token      text check (token is null or char_length(token) <= 4096),
  can_range  boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key (seek_id, user_id)
);

-- Versiones anteriores de este archivo tenían "levantar la mano" (alertas
-- a todo el grupo). Nunca se desplegó; se retira en vez de dejar dos modelos.
drop function if exists public.raise_group_hand(uuid);
drop function if exists public.resolve_group_hand(uuid);
drop function if exists public.get_group_alert(uuid);
drop function if exists public.get_group_alerts(uuid);
drop function if exists public.get_group_alert_push_targets(uuid, uuid);
-- Nombre anterior de authorize_rally_point (antes de separar Auxilio / Punto de encuentro).
drop function if exists public.authorize_beacon_ignition(uuid);
drop table if exists public.safety_group_alerts;

-- Misma clave-en-vault que el resto, minteada de gen_random_uuid() (core
-- Postgres, no pgcrypto — la creación no puede pegar en el trap del
-- search_path).
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'safety_group_key') then
    perform vault.create_secret(
      encode(convert_to(gen_random_uuid()::text || gen_random_uuid()::text, 'utf8'), 'base64'),
      'safety_group_key');
  end if;
end $$;


-- ══════════════════════════════════════════════════════════════════
-- 2. GRANTS Y RLS — todo por RPC, nada por tabla
-- ══════════════════════════════════════════════════════════════════

revoke all on public.device_tokens         from anon, authenticated;
revoke all on public.safety_groups         from anon, authenticated;
revoke all on public.safety_group_members  from anon, authenticated;
revoke all on public.safety_group_messages from anon, authenticated;
revoke all on public.safety_group_seeks         from anon, authenticated;
revoke all on public.safety_group_seek_tokens   from anon, authenticated;

alter table public.device_tokens         enable row level security;
alter table public.safety_groups         enable row level security;
alter table public.safety_group_members  enable row level security;
alter table public.safety_group_messages enable row level security;
alter table public.safety_group_seeks         enable row level security;
alter table public.safety_group_seek_tokens   enable row level security;
-- Sin policies a propósito: sin grant no hay SELECT de todas formas, y sin
-- policy un `grant select on all tables` futuro tampoco abre nada.


-- ══════════════════════════════════════════════════════════════════
-- 3. HELPERS (internos — revocados de todo rol cliente en §6)
-- ══════════════════════════════════════════════════════════════════

-- ¿Este usuario es miembro ACTIVO de un grupo VIVO? Devuelve el grupo.
create or replace function public.bp_safety_group_of(p_user uuid)
returns uuid language sql stable security definer set search_path = public as $$
  select g.id
    from public.safety_group_members m
    join public.safety_groups g on g.id = m.group_id
   where m.user_id = p_user and m.left_at is null
     and g.ended_at is null and g.expires_at > now()
   order by g.created_at desc
   limit 1;
$$;

create or replace function public.bp_safety_group_is_member(p_group uuid, p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1
      from public.safety_group_members m
      join public.safety_groups g on g.id = m.group_id
     where m.group_id = p_group and m.user_id = p_user and m.left_at is null
       and g.ended_at is null and g.expires_at > now());
$$;

create or replace function public.bp_safety_group_code()
returns text language plpgsql volatile security definer set search_path = public as $$
declare
  -- Sin 0/O/1/I/L: el código se dicta en voz alta en un lugar con ruido.
  v_alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_code text;
  v_try int := 0;
begin
  loop
    v_code := '';
    for i in 1..6 loop
      v_code := v_code || substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.safety_groups g
                           where g.code = v_code and g.ended_at is null);
    v_try := v_try + 1;
    if v_try > 20 then raise exception 'code_unavailable'; end if;
  end loop;
  return v_code;
end;
$$;


-- ══════════════════════════════════════════════════════════════════
-- 4. GRUPO: crear, entrar, salir, sacar, cerrar, leer
-- ══════════════════════════════════════════════════════════════════

create or replace function public.create_safety_group(
  p_trip_id uuid default null,
  p_hours   int  default 4
) returns table (group_id uuid, code text, expires_at timestamptz)
language plpgsql security definer set search_path = public, extensions as $$
#variable_conflict use_column
declare
  v_me     uuid := auth.uid();
  v_recent int;
  v_id     uuid;
  v_code   text;
  v_exp    timestamptz;
  v_hours  int := least(greatest(coalesce(p_hours, 4), 1), 12);
begin
  if v_me is null then raise exception 'not_authenticated'; end if;

  if public.bp_safety_group_of(v_me) is not null then
    raise exception 'already_in_group';
  end if;

  if p_trip_id is not null and not exists (
    select 1 from public.trips t
     where t.id = p_trip_id
       and (v_me = t.creator_id or v_me = any(t.member_ids) or v_me = any(t.co_organizer_ids))
  ) then
    raise exception 'not_in_trip';
  end if;

  select count(*) into v_recent from public.safety_groups g
   where g.created_by = v_me and g.created_at > now() - interval '1 hour';
  if v_recent >= 5 then raise exception 'rate_limit_exceeded'; end if;

  v_code := public.bp_safety_group_code();
  v_exp  := now() + make_interval(hours => v_hours);

  insert into public.safety_groups (code, created_by, trip_id, expires_at)
  values (v_code, v_me, p_trip_id, v_exp)
  returning id into v_id;

  insert into public.safety_group_members (group_id, user_id, role)
  values (v_id, v_me, 'leader');

  return query select v_id, v_code, v_exp;
end;
$$;

-- Las dos formas de entrar (código, enlace mágico) pasan por ESTA función,
-- para que las reglas —grupo vivo, cupo, bloqueos, un grupo a la vez— no
-- puedan diferir entre una y otra.
create or replace function public.bp_join_safety_group(p_me uuid, p_group_id uuid)
returns table (group_id uuid, code text, expires_at timestamptz)
language plpgsql security definer set search_path = public, extensions as $$
#variable_conflict use_column
declare
  v_group public.safety_groups%rowtype;
  v_count int;
begin
  -- TODA falla de acá hasta el insert es `return;` (cero filas), NO
  -- `raise exception`. Motivo, y es de seguridad: `check_rate_limit` cuenta el
  -- intento con un `insert ... on conflict do update` en LA MISMA transacción
  -- que esta función, y un `raise` la revierte ENTERA — incluido ese conteo.
  -- Con `raise`, sólo contaban los intentos que acertaban, o sea que el freno
  -- de fuerza bruta no frenaba a nadie. Con cero filas la transacción
  -- commitea y el intento queda contado. El cliente ya trata "sin filas" como
  -- `groupNotFound`. Los `raise` de más abajo (already_in_group, group_full)
  -- ocurren cuando el grupo YA existía y la persona lo conocía: ahí no hay
  -- nada que adivinar.
  select * into v_group from public.safety_groups g
   where g.id = p_group_id and g.ended_at is null and g.expires_at > now()
   for update;
  if not found then return; end if;

  -- EXPULSADO: el líder sacó a esta persona de ESTE grupo. Se trata igual que
  -- un grupo inexistente, para no revelarle nada.
  if exists (select 1 from public.safety_group_members m
              where m.group_id = v_group.id and m.user_id = p_me
                and m.removed_by is not null) then
    return;
  end if;

  -- Ya estoy adentro de ESTE grupo: idempotente (tocar el enlace dos veces
  -- no rompe nada).
  if public.bp_safety_group_is_member(v_group.id, p_me) then
    return query select v_group.id, v_group.code, v_group.expires_at;
    return;
  end if;
  if public.bp_safety_group_of(p_me) is not null then raise exception 'already_in_group'; end if;

  select count(*) into v_count from public.safety_group_members m
   where m.group_id = v_group.id and m.left_at is null;
  if v_count >= 12 then raise exception 'group_full'; end if;

  -- Bloqueo en cualquier dirección con CUALQUIER miembro actual: se trata
  -- igual que un grupo inexistente (cero filas), para no revelar quién está
  -- adentro.
  if exists (
    select 1 from public.safety_group_members m
     where m.group_id = v_group.id and m.left_at is null
       and public.bp_blocked_between(p_me, m.user_id)
  ) then return; end if;

  -- El upsert sólo reabre a quien SE FUE. No toca `removed_by`: un expulsado
  -- nunca llega hasta acá (se cortó arriba), y si alguna vez llegara, esta
  -- línea no le borraría la marca.
  insert into public.safety_group_members (group_id, user_id, role)
  values (v_group.id, p_me, 'member')
  on conflict (group_id, user_id) do update set left_at = null, joined_at = now(), role = 'member';

  return query select v_group.id, v_group.code, v_group.expires_at;
end;
$$;

create or replace function public.join_safety_group(p_code text)
returns table (group_id uuid, code text, expires_at timestamptz)
language plpgsql security definer set search_path = public, extensions as $$
#variable_conflict use_column
declare
  v_me   uuid := auth.uid();
  v_code text := upper(btrim(coalesce(p_code, '')));
  v_gid  uuid;
begin
  if v_me is null then raise exception 'not_authenticated'; end if;

  -- Freno de fuerza bruta. Se cuenta ANTES de mirar el código, así cuentan
  -- todos los intentos —también los mal formados y los que no existen—, y
  -- después de esta línea NINGUNA falla por código es un `raise` (ver el
  -- comentario de `bp_join_safety_group`: un `raise` revierte este conteo).
  -- 8 cada 10 minutos: un humano teclea un código una vez, con suerte dos.
  -- (`rate_limit_exceeded` sí es un `raise` y sí revierte SU incremento, pero
  -- eso no destraba a nadie: el contador queda en el tope y el siguiente
  -- intento vuelve a pasarse.)
  if not public.check_rate_limit('join_safety_group:' || v_me::text, 8, 600) then
    raise exception 'rate_limit_exceeded';
  end if;

  if char_length(v_code) <> 6 then return; end if;

  select g.id into v_gid from public.safety_groups g
   where g.code = v_code and g.ended_at is null and g.expires_at > now();
  if v_gid is null then return; end if;

  return query select * from public.bp_join_safety_group(v_me, v_gid);
end;
$$;

-- ENLACE MÁGICO: barpass://group?id={group_id}. Entra sin pedir el código.
create or replace function public.join_safety_group_by_id(p_group_id uuid)
returns table (group_id uuid, code text, expires_at timestamptz)
language plpgsql security definer set search_path = public, extensions as $$
#variable_conflict use_column
declare v_me uuid := auth.uid();
begin
  if v_me is null then raise exception 'not_authenticated'; end if;
  -- Mismo contador y mismo tope que el código, y por la misma razón: cuenta
  -- todo intento, y las fallas por id son cero filas y no `raise`.
  if not public.check_rate_limit('join_safety_group:' || v_me::text, 8, 600) then
    raise exception 'rate_limit_exceeded';
  end if;
  if p_group_id is null then return; end if;
  return query select * from public.bp_join_safety_group(v_me, p_group_id);
end;
$$;

create or replace function public.leave_safety_group(p_group_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := auth.uid();
  v_role text;
  v_next uuid;
begin
  if v_me is null then raise exception 'not_authenticated'; end if;

  update public.safety_group_members m set left_at = now()
   where m.group_id = p_group_id and m.user_id = v_me and m.left_at is null
  returning m.role into v_role;
  if not found then return; end if;

  -- Sin líder no hay quien saque a nadie ni cierre el grupo: el miembro
  -- más antiguo hereda. Si no queda nadie, se cierra.
  if v_role = 'leader' then
    select m.user_id into v_next from public.safety_group_members m
     where m.group_id = p_group_id and m.left_at is null
     order by m.joined_at limit 1;
    if v_next is null then
      update public.safety_groups g set ended_at = now() where g.id = p_group_id;
    else
      update public.safety_group_members m set role = 'leader'
       where m.group_id = p_group_id and m.user_id = v_next;
    end if;
  end if;
end;
$$;

create or replace function public.remove_safety_group_member(p_group_id uuid, p_user_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := auth.uid();
begin
  if v_me is null then raise exception 'not_authenticated'; end if;
  if not exists (select 1 from public.safety_group_members m
                  where m.group_id = p_group_id and m.user_id = v_me
                    and m.role = 'leader' and m.left_at is null) then
    raise exception 'not_leader';
  end if;
  if p_user_id = v_me then raise exception 'cannot_remove_self'; end if;
  -- Sacar = irse + quedar registrado como expulsado (ver la definición de la
  -- tabla): `bp_join_safety_group` lo rechaza para siempre en ESTE grupo.
  update public.safety_group_members m
     set left_at = now(), removed_by = v_me, removed_at = now()
   where m.group_id = p_group_id and m.user_id = p_user_id and m.left_at is null;
end;
$$;

create or replace function public.end_safety_group(p_group_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := auth.uid();
begin
  if v_me is null then raise exception 'not_authenticated'; end if;
  if not exists (select 1 from public.safety_group_members m
                  where m.group_id = p_group_id and m.user_id = v_me
                    and m.role = 'leader' and m.left_at is null) then
    raise exception 'not_leader';
  end if;
  -- ENDEVENT: cerrar = que deje de ser un grupo vivo YA. Las búsquedas en
  -- curso mueren con él (bp_seek_live exige grupo vivo), y los mensajes se
  -- borran en la purga (§7); mientras tanto ninguna RPC los sirve.
  update public.safety_groups g set ended_at = now()
   where g.id = p_group_id and g.ended_at is null;
end;
$$;

-- Mi grupo vivo, o ninguna fila.
create or replace function public.get_my_safety_group()
returns table (
  group_id uuid, code text, expires_at timestamptz, trip_id uuid,
  my_role text, member_count int
)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_gid uuid;
begin
  if v_me is null then return; end if;
  v_gid := public.bp_safety_group_of(v_me);
  if v_gid is null then return; end if;
  return query
  select g.id, g.code, g.expires_at, g.trip_id,
         (select m.role from public.safety_group_members m
           where m.group_id = g.id and m.user_id = v_me),
         (select count(*)::int from public.safety_group_members m
           where m.group_id = g.id and m.left_at is null)
    from public.safety_groups g
   where g.id = v_gid;
end;
$$;

create or replace function public.get_safety_group_members(p_group_id uuid)
returns table (user_id uuid, display_name text, avatar_url text, role text, joined_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare v_me uuid := auth.uid();
begin
  if v_me is null then return; end if;
  if not public.bp_safety_group_is_member(p_group_id, v_me) then return; end if;
  return query
  select m.user_id, p.display_name, p.avatar_url, m.role, m.joined_at
    from public.safety_group_members m
    join public.profiles p on p.id = m.user_id
   where m.group_id = p_group_id and m.left_at is null
   order by (m.role = 'leader') desc, m.joined_at;
end;
$$;


-- ══════════════════════════════════════════════════════════════════
-- 5. CHAT EFÍMERO Y BUSCAR AL LÍDER
-- ══════════════════════════════════════════════════════════════════

create or replace function public.send_group_message(p_group_id uuid, p_text text)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare
  v_me     uuid := auth.uid();
  v_text   text := btrim(coalesce(p_text, ''));
  v_recent int;
  v_key    text;
  v_id     uuid;
begin
  if v_me is null then raise exception 'not_authenticated'; end if;
  if char_length(v_text) = 0 or char_length(v_text) > 500 then
    raise exception 'message_length';
  end if;
  -- Membresía y vida del grupo se re-verifican en CADA envío: quien salió o
  -- fue sacado, o un grupo que venció, deja de poder escribir en el acto.
  if not public.bp_safety_group_is_member(p_group_id, v_me) then
    raise exception 'not_in_group';
  end if;

  select count(*) into v_recent from public.safety_group_messages m
   where m.sender_id = v_me and m.created_at > now() - interval '1 minute';
  if v_recent >= 20 then raise exception 'rate_limit_exceeded'; end if;

  select s.decrypted_secret into v_key from vault.decrypted_secrets s
   where s.name = 'safety_group_key';
  if v_key is null then raise exception 'chat_key_unavailable'; end if;

  insert into public.safety_group_messages (group_id, sender_id, text_enc)
  values (p_group_id, v_me, pgp_sym_encrypt(v_text, v_key))
  returning id into v_id;
  return v_id;
end;
$$;

-- `p_since` para el poll incremental: el cliente pide sólo lo nuevo. Los
-- mensajes de alguien que me bloqueó, o a quien bloqueé, no se sirven.
create or replace function public.get_group_messages(
  p_group_id uuid,
  p_since    timestamptz default null,
  p_limit    int default 200
) returns table (id uuid, sender_id uuid, sender_name text, text text, created_at timestamptz)
language plpgsql stable security definer set search_path = public, extensions as $$
#variable_conflict use_column
declare
  v_me  uuid := auth.uid();
  v_key text;
begin
  if v_me is null then return; end if;
  if not public.bp_safety_group_is_member(p_group_id, v_me) then return; end if;

  select s.decrypted_secret into v_key from vault.decrypted_secrets s
   where s.name = 'safety_group_key';
  if v_key is null then return; end if;

  return query
  select sub.id, sub.sender_id, sub.sender_name, sub.text, sub.created_at
  from (
    select m.id, m.sender_id, p.display_name as sender_name,
           pgp_sym_decrypt(m.text_enc, v_key) as text, m.created_at
      from public.safety_group_messages m
      join public.profiles p on p.id = m.sender_id
     where m.group_id = p_group_id
       and (p_since is null or m.created_at > p_since)
       and not public.bp_blocked_between(v_me, m.sender_id)
     order by m.created_at desc
     limit greatest(least(coalesce(p_limit, 200), 500), 1)
  ) sub
  order by sub.created_at asc;
end;
$$;

-- ESTADO A. Un miembro (no el líder) busca al líder. Devuelve el id de la
-- búsqueda: el cliente se lo pasa a /api/safety/notify, que manda el push
-- SÓLO al líder. La búsqueda existe aunque el push falle — el líder la ve al
-- abrir el grupo.
create or replace function public.seek_group_leader(p_group_id uuid)
returns table (seek_id uuid, expires_at timestamptz, target_id uuid, target_name text)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_me     uuid := auth.uid();
  v_target uuid;
  v_recent int;
  v_id     uuid;
  v_exp    timestamptz;
  v_name   text;
begin
  if v_me is null then raise exception 'not_authenticated'; end if;
  if not public.bp_safety_group_is_member(p_group_id, v_me) then
    raise exception 'not_in_group';
  end if;

  select m.user_id into v_target from public.safety_group_members m
   where m.group_id = p_group_id and m.role = 'leader' and m.left_at is null
   limit 1;
  if v_target is null then raise exception 'no_leader'; end if;
  -- El líder no se busca a sí mismo: no tiene a quién.
  if v_target = v_me then raise exception 'is_leader'; end if;
  if public.bp_blocked_between(v_me, v_target) then raise exception 'no_leader'; end if;

  -- Una interrupción privilegiada en el teléfono de otro es una herramienta
  -- de acoso si no tiene medidor.
  select count(*) into v_recent from public.safety_group_seeks s
   where s.seeker_id = v_me and s.created_at > now() - interval '1 hour';
  if v_recent >= 6 then raise exception 'rate_limit_exceeded'; end if;

  -- Una búsqueda viva por persona: volver a buscar reemplaza.
  update public.safety_group_seeks s set ended_at = now()
   where s.seeker_id = v_me and s.ended_at is null;

  insert into public.safety_group_seeks (group_id, seeker_id, target_id)
  values (p_group_id, v_me, v_target)
  returning id, safety_group_seeks.expires_at into v_id, v_exp;

  select p.display_name into v_name from public.profiles p where p.id = v_target;
  return query select v_id, v_exp, v_target, v_name;
end;
$$;

-- ¿Sigue viva? Búsqueda sin terminar ni vencer, grupo vivo, el buscador
-- todavía adentro, y el objetivo TODAVÍA es el líder (si el liderazgo pasó a
-- otra persona, esa búsqueda ya no apunta a quien manda).
create or replace function public.bp_seek_live(p_seek_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.safety_group_seeks s
     where s.id = p_seek_id and s.ended_at is null and s.expires_at > now()
       and public.bp_safety_group_is_member(s.group_id, s.seeker_id)
       and exists (select 1 from public.safety_group_members m
                    where m.group_id = s.group_id and m.user_id = s.target_id
                      and m.role = 'leader' and m.left_at is null));
$$;

-- Una búsqueda, para quien está en ella (buscador u objetivo) y nadie más.
-- El cliente la llama al tocar el push, ANTES de abrir el radar.
create or replace function public.get_group_seek(p_seek_id uuid)
returns table (seek_id uuid, group_id uuid, seeker_id uuid, seeker_name text,
               target_id uuid, target_name text, created_at timestamptz,
               expires_at timestamptz, is_live boolean, i_am_target boolean)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare v_me uuid := auth.uid();
begin
  if v_me is null then return; end if;
  return query
  select s.id, s.group_id, s.seeker_id, ps.display_name, s.target_id, pt.display_name,
         s.created_at, s.expires_at, public.bp_seek_live(s.id), (s.target_id = v_me)
    from public.safety_group_seeks s
    join public.profiles ps on ps.id = s.seeker_id
    join public.profiles pt on pt.id = s.target_id
   where s.id = p_seek_id
     and (s.seeker_id = v_me or s.target_id = v_me)
     and not public.bp_blocked_between(s.seeker_id, s.target_id);
end;
$$;

-- Mis búsquedas vivas en este grupo (como buscador o como objetivo): para
-- verlas al abrir la app aunque el push no haya llegado.
create or replace function public.get_group_seeks(p_group_id uuid)
returns table (seek_id uuid, group_id uuid, seeker_id uuid, seeker_name text,
               target_id uuid, target_name text, created_at timestamptz,
               expires_at timestamptz, is_live boolean, i_am_target boolean)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare v_me uuid := auth.uid();
begin
  if v_me is null then return; end if;
  if not public.bp_safety_group_is_member(p_group_id, v_me) then return; end if;
  return query
  select s.id, s.group_id, s.seeker_id, ps.display_name, s.target_id, pt.display_name,
         s.created_at, s.expires_at, true, (s.target_id = v_me)
    from public.safety_group_seeks s
    join public.profiles ps on ps.id = s.seeker_id
    join public.profiles pt on pt.id = s.target_id
   where s.group_id = p_group_id
     and (s.seeker_id = v_me or s.target_id = v_me)
     and public.bp_seek_live(s.id)
     and not public.bp_blocked_between(s.seeker_id, s.target_id)
   order by s.created_at desc;
end;
$$;

-- Cualquiera de los dos termina la búsqueda: "ya me encontró", "dejé de
-- buscar", o el líder que cierra el radar.
create or replace function public.end_group_seek(p_seek_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := auth.uid();
begin
  if v_me is null then raise exception 'not_authenticated'; end if;
  update public.safety_group_seeks s set ended_at = now()
   where s.id = p_seek_id and s.ended_at is null
     and (s.seeker_id = v_me or s.target_id = v_me);
end;
$$;

-- ESTADO C. El buzón de tokens de NearbyInteraction. Sólo las dos personas
-- de la búsqueda, sólo mientras está viva.
create or replace function public.publish_seek_token(p_seek_id uuid, p_token text, p_can_range boolean)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := auth.uid();
begin
  if v_me is null then raise exception 'not_authenticated'; end if;
  if not exists (select 1 from public.safety_group_seeks s
                  where s.id = p_seek_id and (s.seeker_id = v_me or s.target_id = v_me))
     or not public.bp_seek_live(p_seek_id) then
    raise exception 'seek_not_found';
  end if;
  insert into public.safety_group_seek_tokens (seek_id, user_id, token, can_range, updated_at)
  values (p_seek_id, v_me, p_token, coalesce(p_can_range, true), now())
  on conflict (seek_id, user_id) do update
    set token = excluded.token, can_range = excluded.can_range, updated_at = now();
end;
$$;

-- El token DE LA OTRA PERSONA. Levanta `seek_not_found` cuando la búsqueda
-- terminó o venció — un hecho, y no cero filas, porque cero filas significa
-- "todavía no publicó", que es la instrucción contraria para el llamador.
create or replace function public.get_seek_tokens(p_seek_id uuid)
returns table (user_id uuid, display_name text, discovery_token text, can_range boolean,
               token_updated_at timestamptz, expires_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare v_me uuid := auth.uid();
begin
  if v_me is null then raise exception 'not_authenticated'; end if;
  if not exists (select 1 from public.safety_group_seeks s
                  where s.id = p_seek_id and (s.seeker_id = v_me or s.target_id = v_me))
     or not public.bp_seek_live(p_seek_id) then
    raise exception 'seek_not_found';
  end if;
  return query
  select t.user_id, p.display_name, t.token, t.can_range, t.updated_at, s.expires_at
    from public.safety_group_seek_tokens t
    join public.safety_group_seeks s on s.id = t.seek_id
    join public.profiles p on p.id = t.user_id
   where t.seek_id = p_seek_id and t.user_id <> v_me;
end;
$$;

-- ESTADO E. Sólo el OBJETIVO de la búsqueda (el líder) puede encender el
-- punto de encuentro. Un buscador que la llame recibe `not_target`. No puede verificar que
-- el líder esté a menos de 9 m (esa medición es de su teléfono y no llega
-- acá, a propósito): lo que garantiza es QUIÉN, no dónde.
create or replace function public.authorize_rally_point(p_seek_id uuid)
returns table (seek_id uuid, expires_at timestamptz)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_me   uuid := auth.uid();
  v_seek public.safety_group_seeks%rowtype;
begin
  if v_me is null then raise exception 'not_authenticated'; end if;
  select * into v_seek from public.safety_group_seeks s
   where s.id = p_seek_id and (s.seeker_id = v_me or s.target_id = v_me);
  if not found or not public.bp_seek_live(p_seek_id) then
    raise exception 'seek_not_found';
  end if;
  if v_seek.target_id <> v_me then raise exception 'not_target'; end if;

  update public.safety_group_seeks s set lit_at = coalesce(s.lit_at, now())
   where s.id = p_seek_id;
  return query select v_seek.id, v_seek.expires_at;
end;
$$;


-- ══════════════════════════════════════════════════════════════════
-- 6. TOKENS DE PUSH — cliente registra el suyo; el servidor lee los ajenos
-- ══════════════════════════════════════════════════════════════════

create or replace function public.register_device_token(p_token text, p_environment text)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := auth.uid();
begin
  if v_me is null then raise exception 'not_authenticated'; end if;
  if p_environment not in ('sandbox', 'production') then raise exception 'bad_environment'; end if;
  insert into public.device_tokens (token, user_id, environment, updated_at)
  values (p_token, v_me, p_environment, now())
  on conflict (token) do update
    set user_id = excluded.user_id, environment = excluded.environment, updated_at = now();
end;
$$;

-- Cerrar sesión: el teléfono deja de recibir los pushes de esa cuenta.
create or replace function public.unregister_device_token(p_token text)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := auth.uid();
begin
  if v_me is null then raise exception 'not_authenticated'; end if;
  delete from public.device_tokens d where d.token = p_token and d.user_id = v_me;
end;
$$;

-- SÓLO service role (la ruta /api/safety/notify). ESTADO B: los tokens del
-- OBJETIVO de UNA búsqueda — el líder y nadie más — y sólo si quien pide es
-- el buscador. El servidor ya autenticó al usuario; esto es la segunda llave.
-- Nunca devuelve tokens de nadie fuera de esa búsqueda.
create or replace function public.get_seek_push_targets(p_seek_id uuid, p_sender uuid)
returns table (token text, environment text, user_id uuid, seeker_name text,
               expires_at timestamptz, group_id uuid)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  return query
  select d.token, d.environment, s.target_id, ps.display_name, s.expires_at, s.group_id
    from public.safety_group_seeks s
    join public.device_tokens d on d.user_id = s.target_id
    join public.profiles ps on ps.id = s.seeker_id
   where s.id = p_seek_id
     and s.seeker_id = p_sender
     and public.bp_seek_live(s.id)
     and not public.bp_blocked_between(p_sender, s.target_id);
end;
$$;

-- Push silencioso "refrescá el grupo" (mensaje nuevo, alguien entró, el
-- grupo cerró). Mismos destinatarios que arriba pero para un grupo, sin
-- búsqueda de por medio, y sin datos.
create or replace function public.get_group_refresh_push_targets(p_group_id uuid, p_sender uuid)
returns table (token text, environment text, user_id uuid)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  return query
  select d.token, d.environment, m.user_id
    from public.safety_group_members m
    join public.device_tokens d on d.user_id = m.user_id
   where m.group_id = p_group_id and m.left_at is null
     and m.user_id <> p_sender
     and (
       public.bp_safety_group_is_member(p_group_id, p_sender)
       -- El líder que ACABA de cerrar el evento (últimos 2 minutos) todavía
       -- puede avisarle al grupo que se acabó, para que los teléfonos apaguen
       -- el radar y el punto de encuentro en el acto en vez de esperar al próximo poll.
       or exists (
         select 1 from public.safety_groups g
           join public.safety_group_members ml
             on ml.group_id = g.id and ml.user_id = p_sender and ml.role = 'leader'
          where g.id = p_group_id and g.ended_at > now() - interval '2 minutes')
     )
     and not public.bp_blocked_between(p_sender, m.user_id);
end;
$$;

-- APNs devuelve 410 cuando un token murió: la ruta lo borra acá.
create or replace function public.delete_dead_device_tokens(p_tokens text[])
returns integer language plpgsql security definer set search_path = public as $$
declare v_n integer;
begin
  delete from public.device_tokens d where d.token = any(p_tokens);
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

do $$
declare v_sig text;
begin
  foreach v_sig in array array[
    'public.bp_safety_group_of(uuid)',
    'public.bp_safety_group_is_member(uuid, uuid)',
    'public.bp_safety_group_code()',
    'public.bp_join_safety_group(uuid, uuid)',
    'public.bp_seek_live(uuid)',
    'public.create_safety_group(uuid, int)',
    'public.join_safety_group(text)',
    'public.join_safety_group_by_id(uuid)',
    'public.leave_safety_group(uuid)',
    'public.remove_safety_group_member(uuid, uuid)',
    'public.end_safety_group(uuid)',
    'public.get_my_safety_group()',
    'public.get_safety_group_members(uuid)',
    'public.send_group_message(uuid, text)',
    'public.get_group_messages(uuid, timestamptz, int)',
    'public.seek_group_leader(uuid)',
    'public.get_group_seek(uuid)',
    'public.get_group_seeks(uuid)',
    'public.end_group_seek(uuid)',
    'public.publish_seek_token(uuid, text, boolean)',
    'public.get_seek_tokens(uuid)',
    'public.authorize_rally_point(uuid)',
    'public.register_device_token(text, text)',
    'public.unregister_device_token(text)',
    'public.get_seek_push_targets(uuid, uuid)',
    'public.get_group_refresh_push_targets(uuid, uuid)',
    'public.delete_dead_device_tokens(text[])'
  ] loop
    execute format('revoke execute on function %s from public, anon, authenticated', v_sig);
  end loop;
end $$;
-- purge_expired_safety_groups() se crea y se revoca en §7.

grant execute on function public.create_safety_group(uuid, int)              to authenticated;
grant execute on function public.join_safety_group(text)                     to authenticated;
grant execute on function public.join_safety_group_by_id(uuid)               to authenticated;
grant execute on function public.leave_safety_group(uuid)                    to authenticated;
grant execute on function public.remove_safety_group_member(uuid, uuid)      to authenticated;
grant execute on function public.end_safety_group(uuid)                      to authenticated;
grant execute on function public.get_my_safety_group()                       to authenticated;
grant execute on function public.get_safety_group_members(uuid)              to authenticated;
grant execute on function public.send_group_message(uuid, text)              to authenticated;
grant execute on function public.get_group_messages(uuid, timestamptz, int)  to authenticated;
grant execute on function public.seek_group_leader(uuid)                     to authenticated;
grant execute on function public.get_group_seek(uuid)                        to authenticated;
grant execute on function public.get_group_seeks(uuid)                       to authenticated;
grant execute on function public.end_group_seek(uuid)                        to authenticated;
grant execute on function public.publish_seek_token(uuid, text, boolean)     to authenticated;
grant execute on function public.get_seek_tokens(uuid)                       to authenticated;
grant execute on function public.authorize_rally_point(uuid)             to authenticated;
grant execute on function public.register_device_token(text, text)          to authenticated;
grant execute on function public.unregister_device_token(text)              to authenticated;

-- Sólo el servidor (service role), nunca un cliente:
grant execute on function public.get_seek_push_targets(uuid, uuid)           to service_role;
grant execute on function public.get_group_refresh_push_targets(uuid, uuid)  to service_role;
grant execute on function public.delete_dead_device_tokens(text[])           to service_role;


-- ══════════════════════════════════════════════════════════════════
-- 7. PURGA — "efímero" tiene que ser un hecho del esquema, no una promesa
-- ══════════════════════════════════════════════════════════════════
--
-- Un grupo vencido o cerrado se borra una hora después, y con él (cascade)
-- sus miembros, mensajes y búsquedas. Por lotes, con SKIP LOCKED, igual que
-- purge_expired_safety_beacons(). Si el cron no corre la privacidad se
-- degrada primero y en silencio — por eso el heartbeat de abajo.

create or replace function public.purge_expired_safety_groups()
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_n integer := 0;
  v_batch integer;
begin
  loop
    delete from public.safety_groups g
     where g.id in (
       select g2.id from public.safety_groups g2
        where least(g2.expires_at, coalesce(g2.ended_at, g2.expires_at)) < now() - interval '1 hour'
        order by g2.expires_at
        limit 200
        for update skip locked);
    get diagnostics v_batch = row_count;
    v_n := v_n + v_batch;
    exit when v_batch = 0 or v_n >= 10000;
  end loop;

  -- Tokens que nadie refrescó en 90 días: teléfonos que ya no existen.
  delete from public.device_tokens d where d.updated_at < now() - interval '90 days';

  if to_regclass('public.cron_heartbeats') is not null then
    insert into public.cron_heartbeats (job_name, last_run_at)
    values ('purge-safety-groups', now())
    on conflict (job_name) do update set last_run_at = excluded.last_run_at;
  end if;
  return v_n;
end;
$$;

revoke execute on function public.purge_expired_safety_groups()
  from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule('purge-safety-groups')
      where exists (select 1 from cron.job where jobname = 'purge-safety-groups');
    perform cron.schedule('purge-safety-groups', '*/15 * * * *',
                          $c$ select public.purge_expired_safety_groups() $c$);
  else
    raise notice 'pg_cron absent — expired groups are only purged when you run purge_expired_safety_groups() by hand. Corre grid_cron.sql primero.';
  end if;
end $$;


-- ══════════════════════════════════════════════════════════════════
-- 8. VERIFICACIÓN (correr a mano, como usuario real en el SQL editor con
--    `set local role authenticated; set local request.jwt.claims = ...`)
-- ══════════════════════════════════════════════════════════════════
--
--   -- Nadie puede leer las tablas directo:
--   select has_table_privilege('authenticated', 'public.safety_group_seek_tokens', 'select');  -- false
--
--   -- Ningún cliente puede pedir los tokens de push de otros:
--   select has_function_privilege('authenticated',
--     'public.get_seek_push_targets(uuid, uuid)', 'execute');                                  -- false
--
--   -- Máquina de estados, con tres usuarios A (líder), B y C (miembros):
--   select * from create_safety_group();                       -- A
--   select * from join_safety_group_by_id('<group_id>');       -- B, C  (enlace mágico)
--   select * from seek_group_leader('<group_id>');             -- B  → target = A
--   select * from seek_group_leader('<group_id>');             -- A  → is_leader
--   select * from get_group_seek('<seek_id>');                 -- C  → 0 filas (no es parte)
--   select * from authorize_rally_point('<seek_id>');      -- B  → not_target
--   select * from authorize_rally_point('<seek_id>');      -- A  → ok
--
--   -- Cerrar el evento mata la búsqueda y el chat deja de servirse:
--   select end_safety_group('<group_id>');                     -- A
--   select bp_seek_live('<seek_id>');                          -- false
--
--   -- La purga deja el grupo vencido sin filas hijas:
--   select purge_expired_safety_groups();
