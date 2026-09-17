-- Anular un cobro de la barra.
--
-- Lo primero que pide un bartender que apretó el botón equivocado. Sin esto la
-- única salida es que el local le devuelva efectivo a la persona, con el cobro
-- igual de firme en la app: el cliente ve una deuda que ya le pagaron en mano y
-- nosotros no tenemos manera de saber que eso pasó.
--
--
-- LAS TRES DECISIONES QUE MANDAN SOBRE ESTE ARCHIVO
-- --------------------------------------------------
-- 1. NO SE BORRA NADA. El cobro anulado queda, marcado con `voided_at`. Un
--    cobro borrado es un agujero en la contabilidad de la noche: a la mañana
--    siguiente nadie puede distinguir "nunca pasó" de "pasó y alguien lo
--    tapó". La devolución es un movimiento NUEVO de billetera, no la
--    desaparición del viejo — la plata entra y sale, y las dos puntas quedan
--    en `wallet_transactions`.
--
-- 2. ANULAR ES DEL LOCAL, NO DEL USUARIO. Entra por la misma puerta que el
--    cobro: `/api/venue/tab/void` con el `x-venue-secret`. Por eso se verifica
--    `venue_id` — sin esa línea, el secreto filtrado de un bar sirve para
--    anular (y por lo tanto devolver plata de) los cobros de otro.
--
--    Y no hace falta el token del cliente: devolver plata sólo puede
--    beneficiar al cliente. La asimetría del archivo original (secreto
--    autentica al local, token autoriza el cobro) existe porque un cobro le
--    SACA plata a alguien. Una anulación se la devuelve, así que el peor caso
--    de un secreto filtrado acá es que un atacante le regale al local sus
--    propias ventas de esta noche. Es un problema de plata del local, no un
--    problema de seguridad del usuario, y lo acota la ventana de tiempo.
--
-- 3. LA VENTANA ES LA NOCHE, NO LA ETERNIDAD (8 horas desde el cobro). Un
--    turno de barra dura eso; un error se descubre en minutos, no en días.
--    Fuera de la ventana el RPC levanta `void_window_expired` y no toca un
--    centavo: a esa altura la devolución ya no es "corregir un tap", es una
--    disputa, y la resuelve BarPass con el service role mirando la cuenta de
--    las dos partes. Una tablet que puede devolver plata de cobros de hace
--    tres semanas es una tablet que, robada, vacía la caja del local.

-- ═══════════════════════════════════════════════════════════════════
-- 1. LAS COLUMNAS DE LA ANULACIÓN
-- ═══════════════════════════════════════════════════════════════════
alter table public.venue_tab_charges
  add column if not exists voided_at  timestamptz,
  add column if not exists void_reason text,
  -- El movimiento que devolvió la plata. Igual que `wallet_transaction_id` en
  -- el cobro: sin esto, "se anuló" es una afirmación y no un hecho
  -- verificable contra el ledger.
  add column if not exists void_wallet_transaction_id uuid references public.wallet_transactions(id),
  -- El doble tap del bartender nervioso no devuelve el doble. Ver también el
  -- candado por `voided_at` en el RPC: la idempotencia real la da el estado
  -- del cobro, esta clave sólo hace que el reintento devuelva LO MISMO.
  add column if not exists void_idempotency_key text;

alter table public.venue_tab_charges drop constraint if exists venue_tab_charges_void_reason_len;
alter table public.venue_tab_charges add constraint venue_tab_charges_void_reason_len
  check (void_reason is null or char_length(btrim(void_reason)) between 1 and 200);

-- Un cobro anulado tiene las tres marcas o ninguna. Un `voided_at` sin
-- transacción de devolución sería un cobro que el cliente ve tachado y que
-- nunca le volvió a la billetera.
alter table public.venue_tab_charges drop constraint if exists venue_tab_charges_void_is_complete;
alter table public.venue_tab_charges add constraint venue_tab_charges_void_is_complete check (
  (voided_at is null and void_wallet_transaction_id is null and void_idempotency_key is null)
  or (voided_at is not null and void_wallet_transaction_id is not null and void_idempotency_key is not null)
) not valid;

drop index if exists venue_tab_charges_void_key_unique;
create unique index venue_tab_charges_void_key_unique
  on public.venue_tab_charges (void_idempotency_key) where void_idempotency_key is not null;

-- La pantalla de la barra lee "los cobros de esta noche en ESTE local", y sólo
-- eso: por venue y por fecha, descendente.
create index if not exists venue_tab_charges_venue_recent_idx
  on public.venue_tab_charges (venue_id, created_at desc);

-- ═══════════════════════════════════════════════════════════════════
-- 2. EL RPC
-- ═══════════════════════════════════════════════════════════════════
-- `already_voided` es parte del contrato, no un detalle: la tablet necesita
-- distinguir "lo anulaste recién" de "ya estaba anulado" para no decirle al
-- bartender que devolvió plata dos veces.
create or replace function public.void_venue_tab_charge(
  p_charge_id       uuid,
  p_venue_id        uuid,
  p_reason          text,
  p_idempotency_key text
)
returns table (charge_id uuid, amount numeric, voided_at timestamptz, already_voided boolean)
language plpgsql security definer set search_path = public as $$
declare
  -- La noche, no la eternidad. Ver decisión 3 en la cabecera.
  c_window constant interval := interval '8 hours';
  v_id         uuid;
  v_member     uuid;
  v_venue      uuid;
  v_amount     numeric;
  v_created    timestamptz;
  v_voided     timestamptz;
  v_reason     text;
  v_tx         uuid;
begin
  if p_idempotency_key is null or btrim(p_idempotency_key) = '' then
    raise exception 'invalid_idempotency_key';
  end if;

  -- Idempotencia primero, igual que en el cobro: el reintento de una anulación
  -- que ya entró devuelve LA MISMA anulación. Se exige el venue igual en este
  -- camino también — si no, una clave adivinada contaría cobros ajenos.
  select c.id, c.amount, c.voided_at
    into v_id, v_amount, v_voided
    from public.venue_tab_charges c
   where c.void_idempotency_key = p_idempotency_key
     and c.venue_id = p_venue_id;
  if found then
    return query select v_id, v_amount, v_voided, true;
    return;
  end if;

  -- El cobro se bloquea: dos tablets anulando el mismo cobro al mismo tiempo
  -- se serializan acá, y la segunda encuentra `voided_at` ya escrito.
  select c.id, c.member_id, c.venue_id, c.amount, c.created_at, c.voided_at
    into v_id, v_member, v_venue, v_amount, v_created, v_voided
    from public.venue_tab_charges c
   where c.id = p_charge_id
   for update;
  if not found then raise exception 'charge_not_found'; end if;

  -- Un local sólo anula lo suyo. Sin esto el secreto de un bar devuelve la
  -- plata de las ventas de otro.
  if v_venue <> p_venue_id then raise exception 'wrong_venue'; end if;

  -- Ya estaba anulado, con otra clave. NO es un error y NO devuelve de nuevo:
  -- la plata ya volvió una vez, y esa es toda la garantía que importa.
  if v_voided is not null then
    return query select v_id, v_amount, v_voided, true;
    return;
  end if;

  if v_created < now() - c_window then
    raise exception 'void_window_expired';
  end if;

  -- Devuelve la plata. Es un movimiento propio ('topup'), no un borrado del
  -- débito: el ledger tiene que poder mostrar las dos puntas.
  select t.transaction_id into v_tx
    from public.adjust_wallet_balance(v_member, v_amount, 'topup') t;

  v_reason := nullif(btrim(coalesce(p_reason, '')), '');
  update public.venue_tab_charges c
     set voided_at = now(),
         void_reason = left(v_reason, 200),
         void_wallet_transaction_id = v_tx,
         void_idempotency_key = p_idempotency_key
   where c.id = v_id
   returning c.voided_at into v_voided;

  return query select v_id, v_amount, v_voided, false;
end;
$$;

-- ═══════════════════════════════════════════════════════════════════
-- 3. PERMISOS
-- ═══════════════════════════════════════════════════════════════════
-- Igual que `charge_venue_tab`: ni anon ni un usuario logueado pueden llamarlo.
-- Entra sólo por /api/venue/tab/void bajo el service role, y esa ruta exige el
-- x-venue-secret del local. Un usuario que pudiera llamarlo se anularía sus
-- propios tragos después de tomarlos.
revoke all on function public.void_venue_tab_charge(uuid, uuid, text, text)
  from public, anon, authenticated;
