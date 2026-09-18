-- ═══════════════════════════════════════════════════════════════════════
-- SAFETY BEACON — THE SIGNAL
--
-- "Estoy perdido, búsquenme." One person raises a hand; the people they
-- came out with see it and walk over. This file is the channel: the row
-- that says someone is looking, and the mailbox the two phones use to
-- swap NearbyInteraction discovery tokens once one of them starts
-- walking.
--
-- Run in the Supabase SQL editor, AFTER: schema.sql, the_grid.sql
-- (venue_checkins), trips_schema.sql, venue_stories.sql (bp_night_of /
-- bp_night_end), friend_graph_schema.sql (friendships, bp_blocked_between).
-- Idempotent — safe to re-run.
--
--
-- NO PUSH, AND THE DESIGN OWNS THAT
-- ---------------------------------------------------------------------
-- Verified today: nothing in the iOS app calls registerForRemoteNotifi-
-- cations(), there is no device-token table and no APNs sender. So this
-- is a POLLED channel, not a pushed one — get_safety_beacons() is a
-- cheap RPC the client calls while it is in the foreground: cada 30s en
-- reposo, cada 4s cuando hay algo vivo, con desfasaje aleatorio
-- (SafetyBeaconStore.swift). That is enough for the only case that
-- matters: two people in the same building, both with the app open, one
-- of them looking for the other. It is NOT enough to wake a phone in a
-- pocket, and nothing here pretends otherwise. When push exists, it
-- becomes a second delivery path for the same row — no schema change.
--
-- Y ESO TIENE UN PRECIO QUE SE PAGA EN CADA POLL. Mil personas adentro
-- de un bar son ~33 req/s contra get_safety_beacons(), toda la noche,
-- con la misma respuesta vacia casi siempre. El §8 de abajo dice como se
-- mide y que numero es una alarma; el resumen es que el poll vacio tiene
-- que salir por un solo Index Scan sobre expires_at y no tocar ni
-- friendships ni venue_checkins, y que cuando SI hay un faro el permiso
-- se resuelve preguntando "¿lo veo yo?" (bp_beacon_can_see) en vez de
-- calcular la audiencia entera del que levanto la mano. Esa es la razon
-- por la que NO hace falta la tabla de destinatarios materializada que
-- estaba anotada como pendiente.
--
--
-- WHO SEES IT — the one invariant
-- ---------------------------------------------------------------------
--   Nobody who is not a mutually-accepted, non-blocked friend of the
--   person who raised the hand ever sees a beacon. Not one.
--
-- The group a beacon is aimed at is then narrowed further, two ways:
--
--   TRIP MODE (p_trip_id given) — friends ∩ that trip's roster. The trip
--   is the right SCOPE (the five people you actually came with, not your
--   whole friend list), but it cannot be the GUARANTEE: trips' UPDATE
--   policy lets any member rewrite the entire row including member_ids,
--   and redeem_trip_invite() lets anyone holding a code — screenshotted,
--   forwarded, posted — join. An audience defined by that array is an
--   audience anyone can add themselves to. Intersecting it with the
--   friend graph makes the audience unforgeable, because friendship is
--   mutual-accept, one row per canonical pair, and RPC-only to write.
--
--   HERE MODE (no trip) — friends who are checked into the SAME venue,
--   inside the night still in progress. Needs no planning, and it is
--   exactly the set of people who could physically walk over.
--
-- The cost is real and must be shown, not hidden: a trip member who is
-- not a friend in the app will NOT see the beacon. That is why
-- safety_beacon_preflight() exists — so the gap is discovered before the
-- night, at the kitchen table, and not during the emergency.
--
--
-- WHAT IS SHARED, AND WHEN IT STOPS
-- ---------------------------------------------------------------------
-- friend_graph_schema.sql §7 fixes the model: location between friends is
-- OPT-IN, off by default, RECIPROCAL, friends-only, and VENUE GRANULARITY
-- — NEVER COORDINATES. Nothing here loosens that.
--
--  · There is no lat/lng column on either table. Not "unused" — absent.
--    A column that does not exist cannot leak.
--  · The venue on a beacon is read from the raiser's OWN open check-in,
--    which they created by tapping "I'm here". The beacon publishes no
--    position the app did not already have because the person announced
--    it. If they have no open check-in, venue_id is NULL and the UI must
--    say "no dijo dónde está" — never guess.
--  · The beacon also carries a SIGNAL SLOT (signal_index/signal_variant):
--    que color y que ritmo va a parpadear ese telefono. No es posicion y
--    no es dato de la persona — es un numero del 0 al 3 por dos, elegido
--    para que dos faros simultaneos adentro del mismo bar no se vean
--    iguales. Ver el comentario de las columnas en §1.
--  · The note is 140 chars the person typed themselves ("baño del fondo",
--    "afuera, junto al food truck"). Encrypted at rest, same vault +
--    pgcrypto posture as friend_messages.
--  · This is an ACT, not tracking: one row, created by one deliberate tap,
--    that stops existing on its own. Raising a hand does not turn on
--    share_location_with_friends and does not survive the beacon.
--  · It stops when the raiser resolves it, or after 20 minutes, whichever
--    is first — and then the ROW IS DELETED (see §6). There is no beacon
--    history for anyone to page back through, including us.
--
-- 20 minutes, because: the thing this replaces is "where r u" texts, and
-- the useful window is how long it takes to cross a venue and find
-- someone — minutes. Shorter expires while your friend is still pushing
-- through a crowd; longer leaves a stale "I'm lost" hanging on somebody's
-- screen hours later, which is worse than no beacon at all. Re-raising is
-- one tap and is deliberately an explicit act, not an auto-renew.
--
--
-- pgcrypto LIVES IN `extensions`, NOT `public`
-- ---------------------------------------------------------------------
-- This has cost this project two outages (see fix_pgcrypto_search_path.sql).
-- Every function below that touches pgp_sym_encrypt/decrypt is pinned to
-- `search_path = public, extensions`. Both schemas are fixed and non-user-
-- writable, so the pin still closes the SECURITY DEFINER escalation hole.
-- The vault key itself is minted from gen_random_uuid(), which is CORE
-- Postgres (13+) and not pgcrypto — so key creation cannot hit the trap at
-- migration time either.
-- ═══════════════════════════════════════════════════════════════════════

create extension if not exists pgcrypto with schema extensions;
create extension if not exists supabase_vault cascade;


-- ══════════════════════════════════════════════════════════════════
-- 1. TABLES
-- ══════════════════════════════════════════════════════════════════

create table if not exists public.safety_beacons (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  -- NULL = "here mode". Not a foreign-key-enforced audience: see header.
  -- CASCADE, not SET NULL: a trip deleted mid-beacon would otherwise flip
  -- the beacon silently into here-mode and swap its audience underneath
  -- the person who raised it. If the group is gone, the signal aimed at
  -- it is gone too.
  trip_id     uuid references public.trips(id) on delete cascade,
  -- Resolved server-side from the raiser's own open check-in. NULL is a
  -- real, displayable state: we do not know where they are. SET NULL on a
  -- deleted venue fails closed — here-mode with no venue has no audience.
  venue_id    uuid references public.venues(id) on delete set null,
  note_enc    bytea,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null,
  resolved_at timestamptz,
  -- ── QUÉ COLOR Y QUÉ RITMO (la sala, no el grupo) ────────────────────
  -- El cliente ya sabe derivar una señal del id del beacon
  -- (BeaconSignal.derived(fromBeaconId:)): determinístico, sin una ronda
  -- de red, y los dos lados llegan al mismo número. Lo que ESO no puede
  -- hacer es mirar la sala. Dos beacons simultáneos de grupos distintos
  -- en el mismo bar caen en la misma señal 1 vez de cada 10, y entonces
  -- el grupo camina con confianza hacia la persona equivocada — que es
  -- peor que no tener faro.
  --
  -- El servidor sí ve la sala: es el único que conoce todos los beacons
  -- vivos de ese venue. Así que elige el slot MENOS USADO ahí adentro y
  -- lo guarda acá (raise_safety_beacon, §4). Dos enteros y nada más: el
  -- índice en la paleta (0 gold, 1 cyan, 2 green, 3 magenta — el orden de
  -- declaración de BeaconIdentity) y la variante de ritmo (0..3). El
  -- espacio real son 10 combinaciones distintas, no 16, porque varias
  -- variantes repiten ritmo para el mismo color.
  --
  -- NULL NO ES UN ERROR NI UN DEFECTO: significa "no pudimos elegir mejor
  -- que el piso", y el cliente vuelve al derivado del id, que ya funciona.
  -- Pasa exactamente en un caso, y a propósito: venue desconocido (la
  -- persona no tiene check-in abierto). Sin venue no hay sala contra la
  -- cual desempatar, y elegir "contra todos los beacons vivos del país"
  -- sería una distribución PEOR que el hash — sesgada hacia los slots
  -- bajos por gente que no está en la misma habitación — y encima se
  -- vería autoritativa. Un slot elegido contra nada no es un slot
  -- elegido. Se deja NULL y se dice por qué.
  signal_index   smallint,
  signal_variant smallint
);

-- `create table if not exists` no agrega columnas a una tabla que ya
-- existe, así que la idempotencia prometida en el encabezado necesita
-- esto para una base donde ya corrió una revisión anterior del archivo.
alter table public.safety_beacons add column if not exists signal_index   smallint;
alter table public.safety_beacons add column if not exists signal_variant smallint;

-- Los dos juntos o ninguno: media señal no se puede dibujar, y un índice
-- sin variante es justamente la clase de fila que el cliente tendría que
-- adivinar. Fuera de rango es dato corrupto, no un faro tenue.
alter table public.safety_beacons drop constraint if exists safety_beacons_signal_slot;
alter table public.safety_beacons add  constraint safety_beacons_signal_slot check (
  (signal_index is null) = (signal_variant is null)
  and (signal_index   is null or signal_index   between 0 and 3)
  and (signal_variant is null or signal_variant between 0 and 3)
);

-- ── EL ORDEN DE DESPLIEGUE IMPORTA, Y SE PAGA EN LA CALLE ──────────────
-- Un teléfono que no sabe leer estas dos columnas cae al derivado del id
-- (BeaconSignal.derived), y ese número casi nunca coincide con el slot que
-- elige §4. O sea: durante una flota mezclada, el que levanta la mano
-- puede ver DORADO mientras el que lo busca lee VERDE — el fallo exacto
-- que este slot existe para evitar, servido por la migración.
-- Así que el orden es: PRIMERO la app que lee signal_index/signal_variant
-- (SafetyBeacon.signal en SafetyBeaconRepository.swift) llega a las manos,
-- DESPUÉS corre este archivo. Al revés no. Las columnas son aditivas y
-- quedan NULL hasta que §4 empiece a escribirlas, así que una app nueva
-- contra una base sin migrar es el caso benigno: nil → derivado, los dos
-- lados iguales, que es exactamente lo que hay hoy.

-- ── ÍNDICES ────────────────────────────────────────────────────────────
--
-- safety_beacons_live_idx ERA `(expires_at desc) where resolved_at is
-- null`, y ESTABA MUERTO para la única consulta que corre miles de veces
-- por noche. get_safety_beacons() filtra
--     expires_at > now() and (resolved_at is null or resolved_at > now() - 2min)
-- y un índice parcial sólo se puede usar si el WHERE de la consulta
-- IMPLICA el predicado del índice. `(A or B)` no implica `A`. El
-- planificador lo descarta en silencio y hace Seq Scan — en el camino
-- caliente, 33 veces por segundo con mil personas adentro. Lo mismo le
-- pasaba al DELETE de la purga (§6), que filtra por expires_at sin decir
-- nada de resolved_at.
--
-- El reemplazo es un btree común sobre expires_at, y es lo que convierte
-- el poll vacío — el 99,9% de los polls — en un descarte de dos páginas:
-- el scan arranca en now() y no encuentra nada, sin importar cuántas
-- filas viejas haya atrás. También es el índice que usa el DELETE.
drop index if exists public.safety_beacons_live_idx;
create index if not exists safety_beacons_expires_idx
  on public.safety_beacons (expires_at);

create index if not exists safety_beacons_user_idx
  on public.safety_beacons (user_id, created_at desc);

-- El desempate de señales de §4: "todos los beacons vivos de ESTE venue".
-- Parcial por resolved_at is null — acá sí, porque esa consulta lo pide
-- textualmente — así que el índice sólo pesa lo que pesan los beacons sin
-- resolver, que es casi nada.
create index if not exists safety_beacons_venue_live_idx
  on public.safety_beacons (venue_id, expires_at) where resolved_at is null;

-- One row per person per beacon, serving both jobs this piece has:
-- "voy para allá" (acked_at) and the discovery-token mailbox.
--
-- discovery_token is an NIDiscoveryToken, NSKeyedArchived and base64'd by
-- the client. It is opaque, carries no location, and is meaningless
-- outside the NISession that minted it — so it is ephemeral by nature,
-- and this table only has to avoid outliving that session. Two rules do
-- that: the row dies with the beacon (cascade + §6 purge), and the client
-- re-publishes on a heartbeat while its session is alive, so
-- token_updated_at is a genuine liveness signal rather than a timestamp
-- nobody can interpret.
create table if not exists public.safety_beacon_participants (
  beacon_id        uuid not null references public.safety_beacons(id) on delete cascade,
  user_id          uuid not null references public.profiles(id) on delete cascade,
  acked_at         timestamptz,
  discovery_token  text,
  -- FALSE = this phone told us it cannot do NearbyInteraction at all (no
  -- U1/U2 chip, permission refused). Silence is ambiguous — the far side
  -- would wait forever for a token that is never coming — so "I can't"
  -- is said out loud and is a different fact from "not yet".
  can_range        boolean not null default true,
  token_updated_at timestamptz,
  primary key (beacon_id, user_id)
);

-- ESTA TABLA NO CRECE, SE REESCRIBE. Una fila por (beacon, persona), y
-- muere con el beacon (cascade + purga §6), así que la cantidad de filas
-- está acotada por la cantidad de beacons vivos. Lo que sí escribe mucho
-- es el heartbeat: SafetyBeaconTokenChannel republica su token cada 45s
-- mientras la sesión de NearbyInteraction vive, y cada republicación es
-- un UPDATE de la MISMA fila. Eso no agrega filas: agrega tuplas muertas.
--
-- Dos decisiones que mantienen ese churn barato, y una que es una
-- prohibición:
--  · fillfactor 70 deja lugar libre en la página para que el UPDATE sea
--    HOT (la versión nueva vive en la misma página, sin tocar índices) y
--    el espacio se recicle sin esperar a un VACUUM completo.
--  · autovacuum agresivo: con el default (20% de la tabla) una tabla de
--    pocas filas y muchísimos updates junta muertos durante horas.
--  · NUNCA indexar discovery_token ni token_updated_at. Un índice sobre
--    una columna que se actualiza rompe HOT y convierte cada heartbeat en
--    escritura de índice. No hay ninguna consulta que los necesite:
--    get_beacon_tokens() entra siempre por (beacon_id, user_id), que es
--    la PK.
alter table public.safety_beacon_participants set (
  fillfactor = 70,
  autovacuum_vacuum_scale_factor = 0.02,
  autovacuum_analyze_scale_factor = 0.02
);
alter table public.safety_beacons set (
  autovacuum_vacuum_scale_factor = 0.05,
  autovacuum_analyze_scale_factor = 0.05
);


-- ══════════════════════════════════════════════════════════════════
-- 1b. ÍNDICES SOBRE TABLAS PRESTADAS
-- ══════════════════════════════════════════════════════════════════
--
-- Estas tres tablas las define otro archivo; acá sólo se LEEN, pero se
-- leen en el camino caliente, así que los índices que ese camino necesita
-- viven donde está la consulta que los justifica. Agregar un índice es
-- aditivo y no cambia semántica de nadie.
--
-- Nota de operación: `create index` (sin CONCURRENTLY) toma un lock de
-- escritura sobre la tabla mientras construye. A esta escala son
-- segundos; si alguna vez deja de serlo, correrlos de a uno con
-- CONCURRENTLY FUERA de una transacción (el editor SQL de Supabase
-- envuelve el script entero en una, así que ahí no se puede).

-- friendships: el predicado real es `status='accepted' and (user_a=? or
-- user_b=?)`. La PK (user_a, user_b) cubre el lado A; friendships_user_b_idx
-- cubre el lado B pero sin el status, así que cada fila candidata vuelve
-- al heap sólo para descartar un 'pending'. Estos dos parciales lo dejan
-- todo en el índice: el lado derecho del par viaja adentro.
create index if not exists friendships_accepted_a_idx
  on public.friendships (user_a, user_b) where status = 'accepted';
create index if not exists friendships_accepted_b_idx
  on public.friendships (user_b, user_a) where status = 'accepted';

-- user_blocks: la PK cubre (blocker, blocked). bp_blocked_between()
-- pregunta también al revés, y user_blocks_blocked_idx (blocked_id solo)
-- obliga a ir al heap por cada candidato. Con el par completo, el chequeo
-- de bloqueo — que corre por cada beacon candidato, por cada poll — es un
-- index-only scan.
create index if not exists user_blocks_pair_reverse_idx
  on public.user_blocks (blocked_id, blocker_id);

-- venue_checkins: las dos consultas calientes de este archivo preguntan
-- por check-ins ABIERTOS de UNA persona —
--   bp_beacon_venue():    user_id = ?  order by checked_in_at desc limit 1
--   bp_beacon_can_see():  user_id = ?  and venue_id = ?
-- y venue_checkins_user_idx (user_id) las sirve arrastrando toda la
-- historia de esa persona (una fila por cada vez que pisó un bar en su
-- vida) para quedarse con la que no tiene checked_out_at. El parcial
-- indexa sólo los check-ins abiertos, que son unidades por persona, y
-- trae checked_in_at ordenado y venue_id sin ir al heap.
create index if not exists venue_checkins_open_user_idx
  on public.venue_checkins (user_id, checked_in_at desc, venue_id)
  where checked_out_at is null;

-- Minted from core gen_random_uuid(), not pgcrypto — see header.
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'safety_beacon_key') then
    perform vault.create_secret(
      encode(convert_to(gen_random_uuid()::text || gen_random_uuid()::text, 'utf8'), 'base64'),
      'safety_beacon_key');
  end if;
end $$;


-- ══════════════════════════════════════════════════════════════════
-- 2. GRANTS AND RLS
-- ══════════════════════════════════════════════════════════════════
--
-- Table grants are revoked outright: there is NO client SELECT on either
-- table, so there is no `select=*` to get wrong and no column list to
-- keep in sync. Every read is an RPC that re-derives the audience.
-- (A column-level REVOKE under a table-level GRANT is a silent no-op —
-- that is how venue_media.user_id stayed readable for weeks. Revoke the
-- table, grant nothing back.)
--
-- `authenticated` is not an authorization boundary here: signup is free
-- and instant, so "any signed-in user" is "anyone".

revoke all on public.safety_beacons             from anon, authenticated;
revoke all on public.safety_beacon_participants from anon, authenticated;

alter table public.safety_beacons             enable row level security;
alter table public.safety_beacon_participants enable row level security;

-- Deliberately TIGHTER than the RPCs: own rows only, never the audience.
-- These policies are dead code today (no grant to consult them) and exist
-- for exactly one scenario — the day someone runs a blanket
-- `grant select on all tables in schema public to authenticated`, which
-- Supabase templates and onboarding scripts really do. On that day the
-- audience still cannot be read off the table. The audience rule is NOT
-- duplicated here on purpose: two copies of a safety predicate drift, and
-- a drifted second copy is worse than one lock plus a hard stop.
drop policy if exists safety_beacons_select_own on public.safety_beacons;
create policy safety_beacons_select_own on public.safety_beacons
  for select to authenticated using (auth.uid() = user_id);

drop policy if exists safety_beacon_participants_select_own on public.safety_beacon_participants;
create policy safety_beacon_participants_select_own on public.safety_beacon_participants
  for select to authenticated using (auth.uid() = user_id);

-- No insert/update/delete policy anywhere. Every write is an RPC below.


-- ══════════════════════════════════════════════════════════════════
-- 3. HELPERS  (internal — revoked from every client role in §5)
-- ══════════════════════════════════════════════════════════════════

-- The venue a person has publicly announced they are at, right now: their
-- own open check-in, inside the night still in progress at that venue's
-- timezone (the same 6 AM boundary stories and presence use, so a 2 AM
-- check-in still counts as Friday night and a 7 AM one does not resurrect
-- last night). NULL means we do not know, and that is a real answer.
create or replace function public.bp_beacon_venue(p_user uuid)
returns uuid language sql stable security definer set search_path = public as $$
  select c.venue_id
    from public.venue_checkins c
    join public.venues v on v.id = c.venue_id
   where c.user_id = p_user
     and c.checked_out_at is null
     and c.checked_in_at > now() - interval '30 hours'
     and public.bp_night_end(public.bp_night_of(c.checked_in_at, v.timezone), v.timezone) > now()
   order by c.checked_in_at desc
   limit 1
$$;

-- THE audience. One definition, called by every RPC and by the preflight,
-- so what the preflight promises and what the feed delivers cannot drift.
-- Takes the three values rather than a beacon id so the preflight can ask
-- "who WOULD see this" before any row exists.
--
-- Recomputed on every read, never snapshotted: in here-mode a friend who
-- walks in five minutes later can help, and one who leaves stops seeing
-- it. The count returned at raise time is therefore a reading, not a
-- promise — the client must present it as such.
--
-- LA MISMA REGLA, PARA UNA SOLA PERSONA — y el motivo por el que esto
-- aguanta mil teléfonos adentro de un bar.
--
-- bp_beacon_audience() responde "¿QUIÉNES lo ven?" y para eso tiene que
-- recorrer la lista de amigos entera. El feed no necesita esa pregunta:
-- necesita "¿lo veo YO?", que son tres búsquedas por índice y nada más.
-- Con la audiencia completa, un beacon en un bar con mil personas
-- adentro se traducía en mil recorridos del grafo de amistades por
-- minuto — el costo que el propio autor dejó anotado como "esto necesita
-- una tabla de destinatarios materializada". No la necesita: necesitaba
-- dejar de calcular un conjunto para preguntar por un elemento.
--
-- NO ES UNA SEGUNDA COPIA DEL PREDICADO. Es la ÚNICA copia: la audiencia
-- de abajo ahora se define como "mis amigos, filtrados por esto". Dos
-- definiciones de una regla de seguridad se separan con el tiempo y la
-- que se quedó atrás nunca avisa. La verificación (g) de §7 cruza las
-- dos formas y tiene que dar cero diferencias.
create or replace function public.bp_beacon_can_see(
  p_raiser uuid, p_trip_id uuid, p_venue_id uuid, p_viewer uuid
) returns boolean
language sql stable security definer set search_path = public as $$
  select p_raiser is not null
     and p_viewer is not null
     and p_raiser <> p_viewer
     -- Amistad mutua aceptada. Entra por la PK canónica (least, greatest),
     -- así que es una búsqueda, no un recorrido.
     and public.bp_are_friends(p_raiser, p_viewer)
     and not public.bp_blocked_between(p_raiser, p_viewer)
     and (
       (p_trip_id is not null and exists (
          select 1 from public.trips t
           where t.id = p_trip_id
             and (p_viewer = t.creator_id
                  or p_viewer = any(t.member_ids)
                  or p_viewer = any(t.co_organizer_ids))))
       or
       (p_trip_id is null and p_venue_id is not null and exists (
          select 1
            from public.venue_checkins c
            join public.venues v on v.id = c.venue_id
           where c.user_id = p_viewer
             and c.venue_id = p_venue_id
             and c.checked_out_at is null
             and c.checked_in_at > now() - interval '30 hours'
             and public.bp_night_end(public.bp_night_of(c.checked_in_at, v.timezone), v.timezone) > now()))
     )
$$;

create or replace function public.bp_beacon_audience(
  p_raiser uuid, p_trip_id uuid, p_venue_id uuid
) returns table (audience_id uuid)
language sql stable security definer set search_path = public as $$
  select f_id from (
    select case when f.user_a = p_raiser then f.user_b else f.user_a end as f_id
      from public.friendships f
     where f.status = 'accepted'
       and (f.user_a = p_raiser or f.user_b = p_raiser)
  ) friends
  -- El chequeo de amistad que hace can_see es redundante acá (la
  -- enumeración de arriba ya lo garantiza) y cuesta una búsqueda por PK
  -- por amigo. Se paga a propósito: esta función quedó en el camino FRÍO
  -- — la llaman raise (una vez por beacon) y el preflight (cuando la
  -- persona lo pide) — y a cambio hay una sola definición del predicado.
  where public.bp_beacon_can_see(p_raiser, p_trip_id, p_venue_id, f_id)
$$;

-- "Am I allowed to be in this beacon's conversation at all" — the raiser,
-- or someone in the audience. Re-checked on every ack and every token
-- read/write, never once at the start: a block or an unfriend has to take
-- effect mid-beacon.
--
-- Pregunta por UNA persona, así que pregunta con can_see y no arma la
-- audiencia entera. Importa: get_beacon_tokens() lo llama cada 3 segundos
-- mientras dos personas caminan una hacia la otra, y publish_beacon_token
-- otra vez en cada heartbeat.
create or replace function public.bp_beacon_participant(p_beacon_id uuid, p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.safety_beacons b
     where b.id = p_beacon_id
       and (b.user_id = p_user
            or public.bp_beacon_can_see(b.user_id, b.trip_id, b.venue_id, p_user))
  )
$$;

-- ── QUE EL ORDEN DE LOS FILTROS NO DEPENDA DE COMO QUEDARON ESCRITOS ───
--
-- El filtro caliente del feed es
--     b.user_id = uid  or  (bp_are_friends(...) and bp_beacon_can_see(...))
-- y el planificador ordena los términos de un AND por COSTO ESTIMADO
-- (order_qual_clauses). Las dos funciones traen el default —100— así que
-- hoy el empate lo desempata el orden en que están escritas, y que la
-- barata quede primero es una casualidad tipográfica: alguien da vuelta
-- el AND en un refactor y cada poll empieza por la consulta cara, sin que
-- nada falle ni avise.
--
-- Los costos reales no empatan y decirlo lo vuelve una garantía del
-- planificador en vez de una convención:
--   bp_are_friends        1 búsqueda por la PK canónica de friendships.
--   bp_beacon_can_see     esa misma, más user_blocks en los dos sentidos,
--                         más trips o venue_checkins+venues.
--   bp_beacon_venue       venue_checkins + venues + dos funciones de noche.
--   bp_beacon_audience    recorre la lista de amigos ENTERA y llama a
--                         can_see por cada uno. Camino frío a propósito
--                         (raise y preflight); el número alto existe para
--                         que el planificador nunca la elija como
--                         pre-filtro de nada.
-- bp_are_friends NO se toca desde acá: es de friend_graph_schema.sql y la
-- usa media app; cambiarle el costo cambiaría planes que este archivo no
-- mide. Con 100 (su default) contra los 200 de can_see, igual queda
-- primera, que es lo único que este filtro necesita.
alter function public.bp_beacon_can_see(uuid, uuid, uuid, uuid) cost 200;
alter function public.bp_beacon_participant(uuid, uuid)         cost 300;
alter function public.bp_beacon_venue(uuid)                     cost 300;
alter function public.bp_beacon_audience(uuid, uuid, uuid)      cost 2000;


-- ══════════════════════════════════════════════════════════════════
-- 4. RPCs
-- ══════════════════════════════════════════════════════════════════

-- Raise the hand. Returns what the raiser needs to render the confirmation
-- honestly, including how many people can see it right now.
-- `create or replace` NO puede cambiar el tipo de retorno de una funcion
-- que ya existe ("cannot change return type of existing function"), y esta
-- revision agrega signal_index/signal_variant a la tabla devuelta. El drop
-- tira tambien los grants, que §5 vuelve a poner mas abajo.
drop function if exists public.raise_safety_beacon(uuid, text);

create or replace function public.raise_safety_beacon(
  p_trip_id uuid default null,
  p_note text default null
) returns table (
  beacon_id uuid, expires_at timestamptz, venue_id uuid,
  venue_name text, audience_count int,
  signal_index int, signal_variant int
)
language plpgsql security definer set search_path = public, extensions as $$
#variable_conflict use_column
-- The directive above is load-bearing and goes FIRST, before any comment.
-- RETURNS TABLE column names (expires_at, venue_id, …) become PL/pgSQL
-- variables in scope, and a bare one of those in a query silently resolves
-- to the variable instead of the column — the class of bug that broke
-- every chapter-chat load the day get_chapter_messages() shipped. Every
-- reference below is qualified as well; this makes the column win if one
-- ever slips through. Locals are all v_-prefixed, so none collide.
declare
  v_me    uuid := auth.uid();
  v_note  text := nullif(btrim(coalesce(p_note, '')), '');
  v_venue uuid;
  v_recent int;
  v_count  int;
  v_id     uuid;
  v_key    text;
  v_slot_index   smallint;
  v_slot_variant smallint;
begin
  if v_me is null then raise exception 'not_authenticated'; end if;
  if char_length(coalesce(v_note, '')) > 140 then raise exception 'note_too_long'; end if;

  -- No beacon row survives ~80 minutes even si pg_cron (§6) nunca se
  -- agendo. Ver §6 para por que borrar, y no retener, es el default
  -- correcto para esta fila.
  --
  -- ACOTADO DE VERDAD, no "barato". Antes era un DELETE sin limite sobre
  -- toda la tabla, adentro de la transaccion de la llamada que MENOS
  -- puede tardar: la persona ya toco el boton. Sin indice util (ver §1)
  -- eso era un Seq Scan, y su costo crecia con la tabla — o sea, se ponia
  -- peor justo la noche con mas gente. Ahora: 200 filas por vez, por el
  -- indice de expires_at, y SKIP LOCKED para que dos personas que
  -- levantan la mano en el mismo segundo no se esperen entre si. Lo que
  -- quede lo termina el cron; si el cron no existe, lo termina el
  -- siguiente raise.
  delete from public.safety_beacons b
   where b.id in (
     select b2.id from public.safety_beacons b2
      where b2.expires_at < now() - interval '1 hour'
      order by b2.expires_at
      limit 200
      for update skip locked);

  if p_trip_id is not null and not exists (
    select 1 from public.trips t
     where t.id = p_trip_id
       and (v_me = t.creator_id or v_me = any(t.member_ids) or v_me = any(t.co_organizer_ids))
  ) then
    raise exception 'not_in_trip';
  end if;

  -- A privileged interrupt on other people's screens is a harassment tool
  -- if it is unmetered. 12/hour is far above any honest use of a feature
  -- whose window is 20 minutes, and low enough to stop a flood.
  select count(*) into v_recent from public.safety_beacons b
   where b.user_id = v_me and b.created_at > now() - interval '1 hour';
  if v_recent >= 12 then raise exception 'rate_limit_exceeded'; end if;

  v_venue := public.bp_beacon_venue(v_me);

  -- A beacon nobody can see is not a beacon, it is a lie told to someone
  -- who needs help. Refuse loudly instead. The client must say what to do
  -- about it (check in, or pick a plan, or add these people as friends).
  --
  -- VA ACA Y NO DESPUES DEL INSERT, y el motivo es de escala, no de
  -- prolijidad: bp_beacon_audience() recorre la lista de amigos entera —
  -- es la consulta mas cara de esta funcion — y abajo hay un lock por
  -- venue. Calculado despues, un raise condenado (el caso comun del que
  -- toca el boton sin check-in y sin trip) tomaba el lock de SU bar,
  -- recorria el grafo, y recien ahi abortaba: los demas raises de ese
  -- mismo bar se le formaban atras para nada. Calculado aca, el camino
  -- que falla no escribe una fila ni toma un lock. El costo sigue siendo
  -- el mismo para el raise que SI sale, que es una vez por beacon.
  select count(*)::int into v_count
    from public.bp_beacon_audience(v_me, p_trip_id, v_venue);
  if v_count = 0 then raise exception 'no_audience'; end if;

  -- One live beacon per person. Re-raising supersedes rather than stacks,
  -- so nobody's screen ever shows the same person lost twice.
  update public.safety_beacons b set resolved_at = now()
   where b.user_id = v_me and b.resolved_at is null and b.expires_at > now();

  if v_note is not null then
    select s.decrypted_secret into v_key
      from vault.decrypted_secrets s where s.name = 'safety_beacon_key';
  end if;

  -- ── ELEGIR LA SEÑAL CONTRA LA SALA ──────────────────────────────────
  --
  -- Las 10 combinaciones (color, variante) que el cliente sabe dibujar y
  -- que dan un ritmo DISTINTO. No son 16: varias variantes repiten ritmo
  -- para el mismo color, y esas duplicadas no entran.
  --   gold(0):    v0 fastFlicker · v1 slowBlink  · v3 doubleBlink
  --   cyan(1):    v0 doubleBlink · v2 slowBlink
  --   green(2):   v0 slowBlink   · v1 fastFlicker · v2 doubleBlink
  --   magenta(3): v0 solid       · v1 longPulse
  --
  -- La tercera columna es el ORDEN DE PREFERENCIA, y es el desempate
  -- cuando varios slots empatan en uso (al principio de la noche empatan
  -- todos en cero). No es arbitrario:
  --
  --  1-4  las cuatro variantes 0: cuatro colores Y cuatro ritmos
  --       distintos, una biyeccion. Hasta cuatro faros simultaneos en un
  --       bar se distinguen por color, por ritmo, o por los dos — incluso
  --       para un dicromata, que es de quien depende que el ritmo exista.
  --  5-6  primero reusan un RITMO entre colores que NO colapsan entre si:
  --       gold/doubleBlink choca solo con cyan (el par mas separado del
  --       eje azul-amarillo, seguro para cualquier vision), y
  --       cyan/slowBlink solo con green.
  --  7-10 degradados, y hay que decirlo: repiten ritmo sobre pares que SI
  --       colapsan (gold/green para un deuteranope) o repiten color con
  --       ritmos parecidos (magenta solid 100% vs longPulse 80%). A esa
  --       altura la UI tiene que apoyarse en el NOMBRE escrito de la
  --       señal, que es el canal que no se degrada.
  --  >10  se repite el menos usado. Diez faros simultaneos adentro de un
  --       bar ya no es un problema de paleta.
  --
  -- El lock por venue cierra la carrera: dos personas que levantan la
  -- mano en el mismo bar en el mismo instante leerian el mismo conjunto
  -- de vivos y elegirian el mismo slot. Es un lock de transaccion,
  -- alcanza a UN venue, y esta transaccion dura milisegundos. Sin esto la
  -- eleccion es "probablemente" unica, que es exactamente la garantia que
  -- esta funcion existe para no dar.
  if v_venue is not null then
    perform pg_advisory_xact_lock(hashtextextended(v_venue::text, 0));

    select s.idx, s.variant into v_slot_index, v_slot_variant
      from (values (0,0,1), (1,0,2), (2,0,3), (3,0,4),
                   (0,3,5), (1,2,6),
                   (2,2,7), (0,1,8), (2,1,9), (3,1,10))
             as s(idx, variant, pref)
      left join public.safety_beacons b
             on b.venue_id       = v_venue
            and b.resolved_at    is null
            and b.expires_at     > now()
            and b.signal_index   = s.idx
            and b.signal_variant = s.variant
     group by s.idx, s.variant, s.pref
     order by count(b.id), s.pref
     limit 1;
  end if;
  -- v_venue nulo => los dos quedan NULL a proposito. Ver el comentario de
  -- las columnas en §1: sin venue no hay sala contra la cual desempatar, y
  -- el cliente cae al derivado del id, que es el piso que ya funciona.

  insert into public.safety_beacons (user_id, trip_id, venue_id, note_enc, expires_at,
                                     signal_index, signal_variant)
  values (v_me, p_trip_id, v_venue,
          case when v_note is null then null else pgp_sym_encrypt(v_note, v_key) end,
          now() + interval '20 minutes',
          v_slot_index, v_slot_variant)
  returning id into v_id;

  return query
    select v_id, b.expires_at, b.venue_id, v.name, v_count,
           b.signal_index::int, b.signal_variant::int
      from public.safety_beacons b
      left join public.venues v on v.id = b.venue_id
     where b.id = v_id;
end;
$$;

-- "Me encontraron." Raiser only. Resolved beacons stay visible to the
-- audience for two more minutes (see get_safety_beacons) so somebody
-- halfway across the room gets "encontrada" instead of a row that
-- silently vanishes and reads as a bug.
create or replace function public.resolve_safety_beacon(p_beacon_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  update public.safety_beacons b set resolved_at = now()
   where b.id = p_beacon_id and b.user_id = auth.uid() and b.resolved_at is null;
  if not found then raise exception 'beacon_not_found'; end if;
end;
$$;

-- The feed. One call returns both the beacons aimed at me and my own, so
-- the poll is a single request; `is_mine` separates them.
--
-- language sql on purpose: RETURNS TABLE column names become variables
-- inside plpgsql, and a bare `venue_id` or `display_name` there is
-- ambiguous at runtime — the exact bug that broke every chapter-chat load
-- the day it shipped.
--
-- EL COSTO A ESCALA, que es lo que decide si esto sirve o no.
--
-- El cliente pollea cada 30s en reposo y cada 4s cuando hay algo vivo,
-- con desfasaje (SafetyBeaconStore.swift). Mil personas adentro de un bar
-- son ~33 req/s contra esta funcion, constantes, toda la noche. Y el
-- 99,9% de esas llamadas tiene la misma respuesta: no hay nada.
--
-- Por eso ese caso tiene que salir SIN TOCAR friendships ni
-- venue_checkins, y sale:
--
--  1. El unico filtro que arranca la consulta es `b.expires_at > now()`,
--     servido por safety_beacons_expires_idx (§1). Sin beacons vivos el
--     scan arranca en now(), no encuentra nada y devuelve cero filas
--     leyendo dos o tres paginas — sin importar cuantas filas viejas
--     haya atras.
--  2. Todo lo demas — la amistad, el permiso — es un filtro POR FILA
--     CANDIDATA. Con cero candidatas se ejecuta cero veces. Es literal:
--     estan adentro de un OR (`b.user_id = uid  or  ...`), y un OR le
--     prohibe al planificador convertirlos en un join que correria igual.
--  3. Cuando SI hay un beacon vivo, el permiso es bp_beacon_can_see() —
--     tres busquedas por indice — y no la audiencia entera del que
--     levanto la mano. Esa es la diferencia entre "cada poll recorre el
--     grafo de amistades de otro" y "cada poll pregunta por uno mismo",
--     y es lo que vuelve innecesaria la tabla de destinatarios
--     materializada que el autor dejo anotada como pendiente.
--
-- La invariante sigue con DOS cerraduras, como antes. La primera es
-- bp_are_friends(): un beacon de alguien que no es mi amigo mutuo se
-- descarta por PK antes de evaluar nada mas. Cambio la FORMA (era un CTE
-- friend_ids que armaba la lista entera de mis amigos apenas hubiera una
-- fila candidata; ahora es una busqueda por par) y no el efecto: sigue
-- siendo un chequeo independiente que se sostiene aunque can_see dejara
-- de exigir amistad.
--
-- language sql on purpose: RETURNS TABLE column names become variables
-- inside plpgsql, and a bare `venue_id` or `display_name` there is
-- ambiguous at runtime — the exact bug that broke every chapter-chat load
-- the day it shipped. (Ese mismo motivo descarta el `if not exists ...
-- then return; end if;` de plpgsql como short-circuit: el indice hace ese
-- trabajo sin pagar el riesgo.)
--
-- Mismo motivo que en raise: el tipo de retorno cambia, y `create or
-- replace` no puede cambiarlo. §5 repone los grants.
drop function if exists public.get_safety_beacons();

create or replace function public.get_safety_beacons()
returns table (
  id uuid, user_id uuid, display_name text, avatar_url text,
  venue_id uuid, venue_name text, note text,
  created_at timestamptz, expires_at timestamptz, resolved_at timestamptz,
  is_mine boolean, i_acked boolean, ack_count int, ack_names text[],
  signal_index int, signal_variant int
)
language sql stable security definer set search_path = public, extensions as $$
  with me as (select auth.uid() as uid),
  live as (
    select b.*, me.uid as viewer
      from public.safety_beacons b cross join me
     where me.uid is not null
       and b.expires_at > now()
       and (b.resolved_at is null or b.resolved_at > now() - interval '2 minutes')
       and (b.user_id = me.uid
            or (public.bp_are_friends(b.user_id, me.uid)
                and public.bp_beacon_can_see(b.user_id, b.trip_id, b.venue_id, me.uid)))
  )
  select live.id, live.user_id, p.display_name, p.avatar_url,
         live.venue_id, v.name,
         -- NULL if the vault secret is missing, which surfaces as "no
         -- note" rather than an error. The beacon itself still works.
         case when live.note_enc is null then null
              else pgp_sym_decrypt(live.note_enc,
                     (select s.decrypted_secret from vault.decrypted_secrets s
                       where s.name = 'safety_beacon_key')) end,
         live.created_at, live.expires_at, live.resolved_at,
         (live.user_id = live.viewer),
         exists (select 1 from public.safety_beacon_participants q
                  where q.beacon_id = live.id and q.user_id = live.viewer
                    and q.acked_at is not null),
         (select count(*)::int from public.safety_beacon_participants q
           where q.beacon_id = live.id and q.acked_at is not null),
         -- Only the people who HAVE a display name. ack_count above counts
         -- everyone, so "3 answered" with two names renders as "Ana, Meli
         -- y 1 más" instead of inventing a name for the third.
         coalesce((select array_agg(pp.display_name order by q.acked_at)
                     from public.safety_beacon_participants q
                     join public.profiles pp on pp.id = q.user_id
                    where q.beacon_id = live.id and q.acked_at is not null
                      and pp.display_name is not null), '{}'::text[]),
         -- El slot que el servidor eligio contra la sala (§1). NULL = no
         -- habia sala contra la cual elegir; el cliente cae al derivado
         -- del id del beacon, que los dos lados calculan igual.
         live.signal_index::int, live.signal_variant::int
    from live
    join public.profiles p on p.id = live.user_id
    left join public.venues v on v.id = live.venue_id
   order by live.created_at desc
$$;

-- "Voy para allá." The only delivery receipt this channel can honestly
-- produce: without push there is no way to know a beacon was DELIVERED,
-- so the raiser is shown who ANSWERED, and zero answers must read as
-- "nadie confirmó todavía" — never as "nobody saw it".
create or replace function public.acknowledge_safety_beacon(p_beacon_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := auth.uid();
begin
  if v_me is null then raise exception 'not_authenticated'; end if;
  if not exists (select 1 from public.safety_beacons b
                  where b.id = p_beacon_id and b.expires_at > now()) then
    raise exception 'beacon_not_found';
  end if;
  if not public.bp_beacon_participant(p_beacon_id, v_me) then
    raise exception 'beacon_not_found';   -- same error: no probing the audience
  end if;

  insert into public.safety_beacon_participants (beacon_id, user_id, acked_at)
  values (p_beacon_id, v_me, now())
  on conflict (beacon_id, user_id) do update set acked_at = coalesce(
    public.safety_beacon_participants.acked_at, now());
end;
$$;

-- Older 2-arg shape, if an earlier revision of this file was ever run.
drop function if exists public.publish_beacon_token(uuid, text);

-- Publish MY NearbyInteraction discovery token into this beacon. Upsert,
-- so a new NISession (the user left the screen and came back) replaces the
-- dead token instead of stacking a second one. Called on a heartbeat while
-- the session is alive — that is what makes token_updated_at readable as
-- liveness on the other side.
create or replace function public.publish_beacon_token(
  p_beacon_id uuid, p_token text, p_can_range boolean default true
) returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := auth.uid();
begin
  if v_me is null then raise exception 'not_authenticated'; end if;
  -- p_can_range=false is a legitimate publish with no token: "my phone
  -- cannot range, stop waiting for me and look for the colour instead".
  if coalesce(p_can_range, true)
     and (p_token is null or char_length(p_token) = 0 or char_length(p_token) > 4096) then
    -- An archived NIDiscoveryToken is a couple hundred bytes base64'd;
    -- 4096 is slack, not a spec. This is not a place to store payloads.
    raise exception 'invalid_token';
  end if;
  if not exists (select 1 from public.safety_beacons b
                  where b.id = p_beacon_id and b.expires_at > now()
                    and b.resolved_at is null) then
    raise exception 'beacon_not_found';
  end if;
  if not public.bp_beacon_participant(p_beacon_id, v_me) then
    raise exception 'beacon_not_found';
  end if;

  insert into public.safety_beacon_participants
         (beacon_id, user_id, discovery_token, can_range, token_updated_at)
  values (p_beacon_id, v_me,
          case when coalesce(p_can_range, true) then p_token else null end,
          coalesce(p_can_range, true), now())
  on conflict (beacon_id, user_id) do update
    set discovery_token  = excluded.discovery_token,
        can_range        = excluded.can_range,
        token_updated_at = excluded.token_updated_at;
end;
$$;

-- The other side's tokens. Never my own — a phone ranging against itself
-- is a bug, not a feature.
--
-- This RAISES when the beacon is over instead of quietly returning zero
-- rows, because zero rows already means "nobody has published yet". The
-- two are opposite instructions to the caller — keep waiting vs. close the
-- screen — and a channel that cannot tell them apart leaves someone
-- staring at a spinner for a person who has already been found.
--
-- token_updated_at is returned raw and NOT collapsed into a live/dead
-- boolean: a peer whose network dropped stops heartbeating but is STILL
-- rangeable (NearbyInteraction is phone-to-phone and needs no server once
-- the tokens are exchanged), so "stale" does not mean "gone" and the
-- server refuses to say it does.
create or replace function public.get_beacon_tokens(p_beacon_id uuid)
returns table (
  user_id uuid, display_name text, discovery_token text,
  can_range boolean, token_updated_at timestamptz, expires_at timestamptz
)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_expires timestamptz;
begin
  if v_me is null then raise exception 'not_authenticated'; end if;
  select b.expires_at into v_expires from public.safety_beacons b
   where b.id = p_beacon_id and b.expires_at > now() and b.resolved_at is null;
  if v_expires is null then raise exception 'beacon_not_found'; end if;
  if not public.bp_beacon_participant(p_beacon_id, v_me) then
    raise exception 'beacon_not_found';   -- same error: no probing the audience
  end if;

  return query
    select q.user_id, p.display_name, q.discovery_token,
           q.can_range, q.token_updated_at, v_expires
      from public.safety_beacon_participants q
      join public.profiles p on p.id = q.user_id
     where q.beacon_id = p_beacon_id
       and q.user_id <> v_me
       and q.token_updated_at is not null;
end;
$$;

-- Who WOULD see a beacon right now, by name. The honesty valve: this is
-- how the app tells someone "3 of the 6 people on this trip can see a
-- safety signal from you" BEFORE the night, when adding the other three
-- as friends is a calm decision and not an emergency.
create or replace function public.safety_beacon_preflight(p_trip_id uuid default null)
returns table (user_id uuid, display_name text, avatar_url text)
language sql stable security definer set search_path = public as $$
  select p.id, p.display_name, p.avatar_url
    from public.bp_beacon_audience(
           auth.uid(), p_trip_id, public.bp_beacon_venue(auth.uid())) a
    join public.profiles p on p.id = a.audience_id
   where auth.uid() is not null
   order by p.display_name nulls last
$$;


-- ══════════════════════════════════════════════════════════════════
-- 5. EXECUTE GRANTS
-- ══════════════════════════════════════════════════════════════════
--
-- Revoking from PUBLIC alone does nothing: Supabase grants anon and
-- authenticated EXECUTE by name through default privileges, so both are
-- named explicitly before anything is granted back. Every function here
-- is SECURITY DEFINER; an un-revoked one is an unauthenticated hole
-- straight past RLS.

do $$
declare v_sig text;
begin
  foreach v_sig in array array[
    'public.bp_beacon_venue(uuid)',
    'public.bp_beacon_audience(uuid, uuid, uuid)',
    'public.bp_beacon_can_see(uuid, uuid, uuid, uuid)',
    'public.bp_beacon_participant(uuid, uuid)',
    'public.raise_safety_beacon(uuid, text)',
    'public.resolve_safety_beacon(uuid)',
    'public.get_safety_beacons()',
    'public.acknowledge_safety_beacon(uuid)',
    'public.publish_beacon_token(uuid, text, boolean)',
    'public.get_beacon_tokens(uuid)',
    'public.safety_beacon_preflight(uuid)'
  ] loop
    execute format('revoke execute on function %s from public, anon, authenticated', v_sig);
  end loop;
end $$;

-- The four bp_* helpers stay revoked from every client role. That is not
-- tidiness: bp_beacon_audience(raiser, trip, venue) takes arbitrary
-- arguments, so a client holding EXECUTE could enumerate any other user's
-- friend list one uuid at a time. bp_beacon_can_see() is worse, not
-- better, for being cheap: con EXECUTE es un oraculo de "¿son amigos X e
-- Y?" que responde en una busqueda por indice, o sea barrible. Son
-- alcanzables solo desde adentro de las RPC de §4, que fijan el raiser a
-- una fila de beacon real.
grant execute on function public.raise_safety_beacon(uuid, text)   to authenticated;
grant execute on function public.resolve_safety_beacon(uuid)       to authenticated;
grant execute on function public.get_safety_beacons()              to authenticated;
grant execute on function public.acknowledge_safety_beacon(uuid)   to authenticated;
grant execute on function public.publish_beacon_token(uuid, text, boolean) to authenticated;
grant execute on function public.get_beacon_tokens(uuid)           to authenticated;
grant execute on function public.safety_beacon_preflight(uuid)     to authenticated;


-- ══════════════════════════════════════════════════════════════════
-- 6. THE ROW DIES
-- ══════════════════════════════════════════════════════════════════
--
-- A beacon row records that a named person felt lost or unsafe, at a named
-- venue, at a named time. Kept, that is a file on somebody's worst night,
-- exposed to every future bug, dump and subpoena. There is no product
-- reason to keep it: the feature is over in 20 minutes and nothing reads
-- history. So it is deleted, and "no history" becomes a fact about the
-- schema rather than a promise in a privacy policy.
--
-- Two paths, because one of them may not be scheduled: raise_safety_beacon
-- purges opportunistically on every call (§4), and pg_cron does it on a
-- timer for the quiet nights when nobody raises anything.

-- En tandas, no de un saque: un DELETE de una sola sentencia sobre todo
-- lo vencido toma miles de locks de fila a la vez y bloquea el raise que
-- entre justo ahi. 500 por vuelta, por safety_beacons_expires_idx, con
-- SKIP LOCKED para convivir con la purga oportunista de §4. El techo de
-- 50.000 por corrida existe para que un backlog historico (el cron
-- apagado una semana) se coma en varias vueltas de 15 minutos en vez de
-- en una transaccion larguisima.
create or replace function public.purge_expired_safety_beacons()
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_n     integer := 0;
  v_batch integer;
begin
  loop
    delete from public.safety_beacons b
     where b.id in (
       select b2.id from public.safety_beacons b2
        where b2.expires_at < now() - interval '1 hour'
        order by b2.expires_at
        limit 500
        for update skip locked);
    get diagnostics v_batch = row_count;
    v_n := v_n + v_batch;
    exit when v_batch = 0 or v_n >= 50000;
  end loop;

  -- Un cron que se apago solo no avisa, y esta tabla no lo puede delatar:
  -- vacia es indistinguible de "no hubo faros anoche", que es el estado
  -- NORMAL. El heartbeat es la unica diferencia entre las dos. Mismo
  -- patron y misma tabla que refresh_grid_pulses (grid_cron_heartbeat.sql);
  -- el `if` es para no acoplar este archivo a ese orden de ejecucion —
  -- plpgsql planifica cada sentencia recien al ejecutarla, asi que la
  -- rama no tomada no falla aunque la tabla no exista.
  if to_regclass('public.cron_heartbeats') is not null then
    insert into public.cron_heartbeats (job_name, last_run_at)
    values ('purge-safety-beacons', now())
    on conflict (job_name) do update set last_run_at = excluded.last_run_at;
  end if;

  return v_n;   -- participants (and their tokens) cascade with the beacon
end;
$$;

revoke execute on function public.purge_expired_safety_beacons()
  from public, anon, authenticated;

-- ── COMO SE AGENDA, Y QUE PASA SI NO CORRE ─────────────────────────────
--
-- pg_cron ESTA en este proyecto: grid_cron.sql ya lo instala
-- (`create extension pg_cron with schema cron`) y corre
-- refresh_grid_pulses cada 5 minutos. Asi que el camino honesto es
-- pg_cron y no hay alternativa que justificar — pero el bloque queda
-- condicional igual, porque este archivo tiene que poder correr en una
-- base donde grid_cron.sql todavia no corrio, y fallar ahi con "schema
-- cron does not exist" seria abortar toda la migracion por el paso menos
-- importante.
--
-- Si pg_cron NO estuviera: la alternativa real no es un cron externo
-- (Vercel Hobby solo permite uno diario y RECHAZA EL DEPLOY entero si ve
-- una expresion mas frecuente — eso ya rompio todos los pushes desde el
-- 2026-08-23, ver grid_cron.sql). Seria correr a mano
-- `select public.purge_expired_safety_beacons();` y aceptar que la unica
-- purga automatica es la oportunista de §4.
--
-- QUE PASA SI NUNCA CORRE, sin adornos:
--  · La privacidad se degrada primero y en silencio. Cada fila que queda
--    dice que una persona con nombre se sintio perdida o insegura, en un
--    lugar con nombre, a una hora con nombre. El "no guardamos historial"
--    del encabezado deja de ser un hecho del esquema y pasa a ser una
--    promesa que depende de un job.
--  · Funcionalmente NO se rompe nada: la purga oportunista de §4 borra
--    200 filas vencidas en cada raise, asi que una base con actividad se
--    limpia sola; y el feed entra por expires_at > now(), que ignora lo
--    viejo por indice sin importar cuanto haya.
--  · Lo que si empeora despacio: safety_beacon_participants crece
--    pegada a los beacons no purgados (cascade), y los indices se
--    agrandan. Es costo de disco, no de latencia.
-- O sea: si esto se apaga, el que se rompe es el compromiso de
-- privacidad, no la feature — que es exactamente el orden que mas facil
-- se pasa por alto.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule('purge-safety-beacons')
      where exists (select 1 from cron.job where jobname = 'purge-safety-beacons');
    perform cron.schedule('purge-safety-beacons', '*/15 * * * *',
                          $c$ select public.purge_expired_safety_beacons() $c$);
  else
    raise notice 'pg_cron absent — purge runs only on raise_safety_beacon(). Corre grid_cron.sql primero.';
  end if;
end $$;

-- Salud del job (la misma consulta que usa el healthcheck del Grid).
-- Alarma: mas de 30 minutos sin latido, o ninguna fila.
--   select job_name, last_run_at, now() - last_run_at as age
--     from public.cron_heartbeats where job_name = 'purge-safety-beacons';


-- ══════════════════════════════════════════════════════════════════
-- 7. VERIFICATION  (run by hand; every one of these must hold)
-- ══════════════════════════════════════════════════════════════════
--
-- (a) No client role can read either table. Expect 0 rows:
--   select table_name, grantee, privilege_type
--     from information_schema.role_table_grants
--    where table_schema='public'
--      and table_name in ('safety_beacons','safety_beacon_participants')
--      and grantee in ('anon','authenticated');
--
-- (b) anon can execute nothing here. Expect 0 rows:
--   select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
--    where n.nspname='public' and (p.proname like '%beacon%')
--      and has_function_privilege('anon', p.oid, 'EXECUTE');
--
-- (c) The audience helpers are not client-callable. Expect 0 rows:
--   select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
--    where n.nspname='public' and p.proname like 'bp_beacon%'
--      and has_function_privilege('authenticated', p.oid, 'EXECUTE');
--
-- (d) pgcrypto is reachable from the two functions that need it. Expect
--     both to show {search_path=public, extensions}:
--   select p.proname, p.proconfig from pg_proc p
--     join pg_namespace n on n.oid=p.pronamespace
--    where n.nspname='public'
--      and p.proname in ('raise_safety_beacon','get_safety_beacons');
--
-- (e) No coordinates exist to leak. Expect 0 rows:
--   select column_name from information_schema.columns
--    where table_schema='public'
--      and table_name in ('safety_beacons','safety_beacon_participants')
--      and column_name in ('lat','lng','latitude','longitude','geom','location');
--
-- (f) A non-friend in the same trip sees nothing. As A (in trip T), raise
--     with p_trip_id=T; as B (also in T, NOT an accepted friend of A),
--     get_safety_beacons() must return 0 rows. Accept the friendship and
--     it must then return exactly 1.
--
-- (g) Blocking severs it mid-beacon. With the beacon live, B blocks A:
--     get_safety_beacons() as B → 0 rows, and
--     acknowledge_safety_beacon(id) as B → beacon_not_found.
--
-- (h) It expires on its own. Raise one, then:
--       update public.safety_beacons set expires_at = now() - interval '1s'
--        where id = '<id>';
--     get_safety_beacons() must return 0 rows for both sides.
--
-- (i) Nothing is retained. After (h), call raise_safety_beacon() again,
--     then: select count(*) from public.safety_beacons
--            where expires_at < now() - interval '1 hour';   -- 0
--
-- (j) LAS DOS FORMAS DEL PREDICADO NO SE SEPARARON. bp_beacon_audience()
--     enumera y bp_beacon_can_see() responde por uno; la audiencia se
--     define en terminos de can_see, asi que esto tiene que dar dos
--     numeros iguales. Correr en staging: la segunda mitad recorre
--     profiles entera a proposito, para que no haya forma de que un bug
--     de enumeracion se esconda.
--       select
--         (select count(*) from public.bp_beacon_audience(
--                 '<raiser>'::uuid, null, '<venue>'::uuid))            as via_audience,
--         (select count(*) from public.profiles p
--           where public.bp_beacon_can_see(
--                 '<raiser>'::uuid, null, '<venue>'::uuid, p.id))      as via_can_see;
--
-- (k) DOS FAROS EN EL MISMO BAR NO COMPARTEN SEÑAL. Levantar la mano
--     desde 5 cuentas distintas con check-in abierto en el MISMO venue y
--     mirar los slots: con 10 o menos vivos ahi, cada count tiene que ser
--     1, y los primeros cuatro tienen que ser (0,0) (1,0) (2,0) (3,0) —
--     cuatro colores y cuatro ritmos distintos.
--       select signal_index, signal_variant, count(*)
--         from public.safety_beacons
--        where venue_id = '<venue>'::uuid
--          and resolved_at is null and expires_at > now()
--        group by 1, 2 order by 3 desc;
--
-- (l) EL SLOT NULO SIGNIFICA LO QUE DICE: no habia sala. Expect 0 rows —
--     un beacon con venue conocido y sin slot es un bug del chooser, no
--     una degradacion aceptable.
--       select count(*) from public.safety_beacons
--        where venue_id is not null and signal_index is null;


-- ══════════════════════════════════════════════════════════════════
-- 8. MEDIR EL PLAN, NO ADIVINARLO
-- ══════════════════════════════════════════════════════════════════
--
-- Las RPC son SECURITY DEFINER y leen auth.uid(), y un EXPLAIN sobre una
-- llamada a funcion muestra un `Function Scan` y nada de adentro
-- (auto_explain no esta disponible en Supabase). Asi que lo que se mide
-- es el CUERPO de la consulta caliente con un uid literal, y aparte el
-- tiempo total de la RPC de verdad.
--
-- Antes de la primera medicion, para que los numeros signifiquen algo:
--   analyze public.safety_beacons;
--   analyze public.safety_beacon_participants;
--   analyze public.friendships;
--   analyze public.venue_checkins;
--
-- ── (1) EL POLL VACIO — el 99,9% de las llamadas ──────────────────────
-- Reemplazar el uuid por el de una cuenta de prueba real.
--
--   explain (analyze, buffers, verbose)
--   with me as (select '<uid>'::uuid as uid)
--   select b.id
--     from public.safety_beacons b cross join me
--    where me.uid is not null
--      and b.expires_at > now()
--      and (b.resolved_at is null or b.resolved_at > now() - interval '2 minutes')
--      and (b.user_id = me.uid
--           or (public.bp_are_friends(b.user_id, me.uid)
--               and public.bp_beacon_can_see(b.user_id, b.trip_id, b.venue_id, me.uid)));
--
-- ESPERADO: `Index Scan using safety_beacons_expires_idx`, rows=0,
--   `Buffers: shared hit=2..4`, Execution Time < 0.5 ms, y NI UNA
--   mencion de friendships, user_blocks, trips o venue_checkins.
-- ALARMA:
--   · `Seq Scan on safety_beacons` — el indice de §1 no existe o no se
--     eligio. Esto es lo unico de toda la lista que se degrada con el
--     tamaño de la tabla, o sea lo unico que explota a escala.
--   · cualquier nodo sobre friendships o venue_checkins con cero filas
--     candidatas — significa que el planificador dejo de evaluar los
--     predicados por fila. El OR es lo que se lo impide; si alguien lo
--     "simplifica" sacando la rama `b.user_id = me.uid`, esto vuelve.
--   · `Buffers: shared hit` que crece noche a noche con la misma
--     respuesta vacia — la purga de §6 no esta corriendo.
--
-- FALSA ALARMA QUE VA A APARECER LA PRIMERA VEZ: en una base de desarrollo
--   con 3 filas, `Seq Scan` es la eleccion CORRECTA y cuesta una pagina —
--   leer la tabla entera es mas barato que abrir el indice, y el
--   planificador tiene razon. La medicion solo significa algo con la tabla
--   cargada: insertar unos miles de beacons vencidos, `analyze`, y recien
--   ahi exigir el Index Scan. Medido en vacio, esto aprueba cualquier cosa.
--
-- ── (2) UN FARO VIVO, EL CASO QUE IMPORTA ─────────────────────────────
-- Misma consulta con un beacon vivo de un amigo en mi mismo venue.
-- ESPERADO: la misma Index Scan, rows=1, y el Filter mostrando
--   `bp_are_friends` y `bp_beacon_can_see`. Buffers shared hit < 40.
--   Execution Time < 2 ms.
-- ALARMA: buffers proporcionales a mi cantidad de amigos (ej. 500+ con
--   200 amigos) — es la firma de que se volvio a calcular la AUDIENCIA
--   entera en vez de preguntar por uno. Es el costo que esta revision
--   saca, y el unico que crece con la cantidad de gente adentro del bar.
--
-- ── (3) LA RPC ENTERA, DE PUNTA A PUNTA ───────────────────────────────
--   begin;
--     set local role authenticated;
--     set local request.jwt.claims = '{"sub":"<uid>","role":"authenticated"}';
--     explain (analyze, buffers) select * from public.get_safety_beacons();
--   rollback;
-- ESPERADO (sin faros vivos): Execution Time < 1 ms. Con 33 req/s eso es
--   ~3% de un core. ALARMA: > 10 ms vacio; a 33 req/s ya es un core
--   entero para contestar "no hay nada".
--
-- ── (4) LA PURGA ──────────────────────────────────────────────────────
--   explain (analyze, buffers)
--   select b2.id from public.safety_beacons b2
--    where b2.expires_at < now() - interval '1 hour'
--    order by b2.expires_at limit 500;
-- ESPERADO: `Index Scan using safety_beacons_expires_idx`, sin Sort.
-- ALARMA: `Seq Scan` + `Sort` — el DELETE de §4 corre adentro de la
--   transaccion de alguien que acaba de tocar el boton de emergencia.
--
-- ── (5) EL DESEMPATE DE SEÑALES ───────────────────────────────────────
--   explain (analyze, buffers)
--   select b.signal_index, b.signal_variant
--     from public.safety_beacons b
--    where b.venue_id = '<venue>'::uuid
--      and b.resolved_at is null and b.expires_at > now();
-- ESPERADO: `Index Scan using safety_beacons_venue_live_idx`, buffers < 5.
--
-- ── (6) NINGUN INDICE MUERTO ──────────────────────────────────────────
-- Despues de una noche real con trafico:
--   select relname, indexrelname, idx_scan,
--          pg_size_pretty(pg_relation_size(indexrelid)) as size
--     from pg_stat_user_indexes
--    where relname in ('safety_beacons', 'safety_beacon_participants',
--                      'friendships', 'user_blocks', 'venue_checkins')
--    order by idx_scan;
-- ESPERADO: safety_beacons_expires_idx con el idx_scan mas alto de todos
--   (un scan por poll). friendships_accepted_a_idx/_b_idx y
--   venue_checkins_open_user_idx con scans > 0.
-- ALARMA: idx_scan = 0 en cualquiera de los que agrega §1/§1b — ese
--   indice se esta pagando en cada escritura y no devuelve nada; hay que
--   entender por que no se elige (un cast, un `or`, un parcial cuyo
--   predicado la consulta no implica — que es exactamente como murio el
--   safety_beacons_live_idx original) y arreglarlo o tirarlo.
-- NOTA aparte, fuera de este archivo: friendships_status_idx
--   (friend_graph_schema.sql:144) indexa una columna de dos valores. Un
--   btree asi no se elige nunca y se escribe siempre. No lo toco desde
--   aca porque no es mio, pero aparece en esta misma consulta con
--   idx_scan = 0 y vale la pena confirmarlo antes de tirarlo.
--
-- ── (7) EL CHURN DEL BUZON DE TOKENS ──────────────────────────────────
--   select relname, n_live_tup, n_dead_tup, n_tup_upd, n_tup_hot_upd,
--          round(100.0 * n_tup_hot_upd / nullif(n_tup_upd, 0), 1) as hot_pct,
--          last_autovacuum
--     from pg_stat_user_tables
--    where relname in ('safety_beacons', 'safety_beacon_participants');
-- ESPERADO: hot_pct > 95 en safety_beacon_participants (el heartbeat cada
--   45s reescribe la misma fila y con fillfactor 70 entra en la misma
--   pagina), y n_dead_tup que baja solo.
-- ALARMA: hot_pct < 80 — alguien indexo discovery_token o
--   token_updated_at y cada heartbeat volvio a ser escritura de indice.
--   n_live_tup en safety_beacon_participants creciendo sin parar mientras
--   safety_beacons se mantiene chica es imposible (cascade): si pasa, la
--   FK se cayo.
--
-- ── (8) EL TERMINO QUE SI CRECE, Y NO ES EL QUE PARECE ────────────────
--
-- Vale decirlo sin adornos, porque es lo unico de este diseño que empeora
-- con el exito: el costo de UN poll es proporcional a la cantidad de
-- beacons vivos EN TODO EL SISTEMA, no a los de mi bar. El filtro arranca
-- por `expires_at > now()`, que es global — no hay forma de indexar "los
-- de mi bar" sin que el que pollea diga en que bar esta, y el que pollea
-- muchas veces no esta en ninguno (mira el faro de un amigo desde afuera).
-- Por cada fila candidata se pagan dos llamadas a funcion.
--
-- Los numeros, para no discutir de memoria. Una llamada a una funcion SQL
-- SECURITY DEFINER no se puede inlinear (por eso mismo: si se inlineara,
-- perderia el definer), asi que cuesta un arranque de executor, del orden
-- del microsegundo, ademas de sus busquedas por indice:
--   · 10 faros vivos en el pais  → ~20 llamadas por poll. Invisible.
--   · 500 faros vivos a la vez   → ~1000 llamadas por poll; con 1000 polls
--     por segundo (30.000 personas con la app abierta) es del orden de un
--     core entero dedicado a contestar "no hay nada para vos".
-- O sea: aguanta miles de personas polleando con pocos faros vivos —que es
-- la noche real— y se pone caro con CIENTOS DE FAROS SIMULTANEOS, que hoy
-- no existe y hay que medir antes de creer.
--
-- Como se mide (no hace falta trafico: alcanza con poblar la tabla):
--   insert into public.safety_beacons (user_id, venue_id, expires_at)
--   select p.id, null, now() + interval '20 minutes'
--     from public.profiles p limit 500;          -- en STAGING, nunca en prod
--   analyze public.safety_beacons;
--   -- y correr (1) otra vez, con el mismo uid de prueba.
-- ESPERADO: Execution Time que sube de forma LINEAL con esa cantidad
--   (500 filas ≈ 500× el trabajo por fila), y sigue por debajo de 5 ms.
-- ALARMA: > 20 ms con 500 vivos. Ahi recien vale la pena el arreglo, y el
--   arreglo NO es la tabla materializada de destinatarios: es angostar las
--   candidatas antes de llamar a nada — `b.user_id in (select ...mis
--   amigos...)` como semi-join, que con cero candidatas el executor ni
--   construye (el hash join pide una fila del lado externo antes de armar
--   la tabla hash). Se deja escrito y NO hecho a proposito: hoy cambiaria
--   un costo medible por uno que depende de un detalle del executor, para
--   ganar microsegundos que nadie esta pagando.
--
-- ── (9) EL TECHO DE VERDAD NO ESTA EN POSTGRES ────────────────────────
--
-- Mil personas adentro de un bar son ~33 req/s contra get_safety_beacons()
-- y la consulta contesta en menos de 1 ms, o sea ~3% de un core. Lo que se
-- llena primero es lo de adelante: cada poll es un request HTTPS a
-- PostgREST con verificacion de JWT y una conexion del pool. Antes de
-- culpar a la base cuando esto se caiga en una noche grande, mirar
-- (Supabase → Reports → API / Database):
--   · `client_connections` y conexiones rechazadas del pooler,
--   · p95 de latencia de PostgREST comparado con el Execution Time de (3):
--     si la consulta tarda 0,8 ms y el request 300 ms, el problema no es
--     esta consulta y ninguna optimizacion de SQL lo va a mover.
-- Y la palanca mas barata no esta ni en la base ni en PostgREST: esta en
-- SafetyBeaconStore.swift. 30s en reposo y 4s cuando hay algo vivo, con
-- desfasaje aleatorio — bajar el reposo a 10s TRIPLICA el trafico de toda
-- la noche para mejorar el unico momento en que ya se pollea cada 4s.
--
-- NOTA sobre el vault, que sorprende: la clave se lee con
-- `(select s.decrypted_secret from vault.decrypted_secrets s where ...)`,
-- una subconsulta SIN correlacion — Postgres la convierte en un InitPlan y
-- lo evalua UNA vez por llamada, y solo cuando alguna fila lo necesita.
-- El poll vacio no desencripta nada. Si alguien la "arregla" metiendola
-- adentro de un join o de un lateral, pasa a ser por fila y cada poll con
-- faros vivos paga una desencriptacion AEAD del secreto ademas del
-- pgp_sym_decrypt de la nota.
