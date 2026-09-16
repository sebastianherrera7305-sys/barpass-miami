-- La cuenta: pagar en la barra sin tarjeta, solo o con tu gente.
--
-- El problema real de un club no es cobrar: es que el cuello de botella sea
-- humano. Esperás a que el bartender te vea, después esperás el POS, y la
-- tanda manda a uno a la barra que pierde veinte minutos de su noche.
--
-- Acá el bartender escanea y listo. Y la parte que nadie tiene: la cuenta
-- puede ser de un grupo, con cada uno viendo lo que consumió — sin que
-- ninguno tenga que fiarse de otro ni pelear al final de la noche.
--
--
-- LA DECISIÓN DE SEGURIDAD QUE MANDA SOBRE TODO ESTE ARCHIVO
-- ----------------------------------------------------------
-- El local NUNCA cobra "a un usuario". Cobra contra un TOKEN que la persona
-- acaba de mostrar en su teléfono: de un solo uso, con vencimiento corto y
-- con un tope de monto que el usuario aprobó.
--
-- Por qué importa: el secreto de venue (x-venue-secret) vive en la tablet de
-- la puerta y en el bolsillo de un empleado que rota cada tres meses. Si ese
-- secreto pudiera cobrarle a cualquiera por su user_id, el día que se filtre
-- —y se filtra— alguien vacía todas las billeteras del catálogo desde su
-- casa. Con tokens, el peor caso de un secreto filtrado es cobrarle de más a
-- alguien que justo está parado en esa barra con el código abierto, y el tope
-- de monto acota hasta eso.
--
-- Esa asimetría es todo el diseño: el secreto del local autentica al LOCAL;
-- el token autoriza EL COBRO. Hacen falta los dos.

-- ═══════════════════════════════════════════════════════════════════
-- 1. LA CUENTA
-- ═══════════════════════════════════════════════════════════════════
create table if not exists public.venue_tabs (
  id         uuid primary key default gen_random_uuid(),
  venue_id   uuid not null references public.venues(id) on delete cascade,
  -- Quien la abrió. En una cuenta de grupo es el que invita, no el que paga
  -- todo: cada consumo lo paga quien lo consumió (ver venue_tab_charges).
  owner_id   uuid not null references auth.users(id) on delete cascade,
  -- Código corto para que un amigo se sume sin escanear nada. Seis caracteres
  -- sin vocales: no se puede leer como una palabra ni confundir 0 con O.
  join_code  text not null unique,
  status     text not null default 'open' check (status in ('open', 'closed')),
  opened_at  timestamptz not null default now(),
  closed_at  timestamptz
);

-- Una sola cuenta abierta por persona y por local: dos cuentas abiertas a la
-- vez es el estado desde el que se cobra dos veces.
create unique index if not exists venue_tabs_one_open_per_owner
  on public.venue_tabs (owner_id, venue_id) where status = 'open';

create index if not exists venue_tabs_venue_idx on public.venue_tabs (venue_id, status);

-- ═══════════════════════════════════════════════════════════════════
-- 2. QUIÉN ESTÁ EN LA CUENTA
-- ═══════════════════════════════════════════════════════════════════
create table if not exists public.venue_tab_members (
  tab_id    uuid not null references public.venue_tabs(id) on delete cascade,
  user_id   uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  left_at   timestamptz,
  primary key (tab_id, user_id)
);

-- ═══════════════════════════════════════════════════════════════════
-- 3. CADA CONSUMO
-- ═══════════════════════════════════════════════════════════════════
create table if not exists public.venue_tab_charges (
  id          uuid primary key default gen_random_uuid(),
  tab_id      uuid not null references public.venue_tabs(id) on delete cascade,
  -- Quién lo consumió Y quién lo paga. No hay "el que invita paga todo":
  -- eso es lo que hace que nadie quiera abrir la cuenta del grupo.
  member_id   uuid not null references auth.users(id) on delete cascade,
  venue_id    uuid not null references public.venues(id) on delete cascade,
  description text not null check (char_length(btrim(description)) between 1 and 200),
  -- Lo que se cobró, tal cual, para que el recibo no dependa de que la carta
  -- no cambie después.
  items       jsonb not null default '[]'::jsonb,
  amount      numeric(10,2) not null check (amount > 0 and amount <= 1000),
  -- El movimiento de billetera que lo pagó: sin esto un cobro es una
  -- afirmación, no un hecho verificable.
  wallet_transaction_id uuid references public.wallet_transactions(id),
  -- Un doble tap del bartender, o un reintento por señal mala, no es un
  -- segundo trago.
  idempotency_key text not null unique,
  created_at  timestamptz not null default now()
);

create index if not exists venue_tab_charges_tab_idx on public.venue_tab_charges (tab_id, created_at desc);
create index if not exists venue_tab_charges_member_idx on public.venue_tab_charges (member_id, created_at desc);

-- ═══════════════════════════════════════════════════════════════════
-- 4. EL TOKEN QUE EL BARTENDER ESCANEA
-- ═══════════════════════════════════════════════════════════════════
-- Lo genera el teléfono del usuario, dura poco, sirve una vez y tiene tope.
create table if not exists public.venue_tab_scan_tokens (
  token      text primary key,
  tab_id     uuid not null references public.venue_tabs(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  -- El techo que la persona aprobó al abrir el código. Un bartender no puede
  -- cobrar $400 contra un código que se mostró para pagar un trago.
  max_amount numeric(10,2) not null check (max_amount > 0 and max_amount <= 1000),
  expires_at timestamptz not null,
  used_at    timestamptz,
  used_by_charge uuid references public.venue_tab_charges(id),
  created_at timestamptz not null default now()
);

create index if not exists venue_tab_scan_tokens_tab_idx on public.venue_tab_scan_tokens (tab_id, expires_at desc);

-- ═══════════════════════════════════════════════════════════════════
-- 5. RLS — cada uno ve su cuenta y la de su grupo, nadie ve la ajena
-- ═══════════════════════════════════════════════════════════════════
alter table public.venue_tabs            enable row level security;
alter table public.venue_tab_members     enable row level security;
alter table public.venue_tab_charges     enable row level security;
alter table public.venue_tab_scan_tokens enable row level security;

-- Sin recursión: la pertenencia se resuelve en una función definer, porque
-- una policy sobre venue_tabs que consulte venue_tab_members cuya policy
-- consulte venue_tabs se muerde la cola y Postgres aborta la consulta.
create or replace function public.bp_is_tab_member(p_tab uuid, p_user uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from public.venue_tab_members m
    where m.tab_id = p_tab and m.user_id = p_user and m.left_at is null
  );
$$;

drop policy if exists "tabs visible to their members" on public.venue_tabs;
create policy "tabs visible to their members" on public.venue_tabs
  for select to authenticated
  using (owner_id = auth.uid() or public.bp_is_tab_member(id, auth.uid()));

drop policy if exists "tab members visible to the tab" on public.venue_tab_members;
create policy "tab members visible to the tab" on public.venue_tab_members
  for select to authenticated
  using (user_id = auth.uid() or public.bp_is_tab_member(tab_id, auth.uid()));

-- El grupo ve TODO lo que se consumió en la cuenta, no sólo lo propio: ese es
-- el punto de la cuenta compartida, y es lo que evita la pelea del final.
drop policy if exists "charges visible to the tab" on public.venue_tab_charges;
create policy "charges visible to the tab" on public.venue_tab_charges
  for select to authenticated
  using (member_id = auth.uid() or public.bp_is_tab_member(tab_id, auth.uid()));

-- Los tokens no los lee nadie: son una capacidad, no información. El teléfono
-- que lo generó ya lo tiene en la respuesta del RPC.
-- (Sin policy de select = nadie, salvo service role.)

-- Nada de escritura directa desde un cliente: todo pasa por los RPC de abajo.
revoke insert, update, delete on public.venue_tabs            from anon, authenticated;
revoke insert, update, delete on public.venue_tab_members     from anon, authenticated;
revoke insert, update, delete on public.venue_tab_charges     from anon, authenticated;
revoke all                    on public.venue_tab_scan_tokens from anon, authenticated;

-- ═══════════════════════════════════════════════════════════════════
-- 6. ABRIR / SUMARSE
-- ═══════════════════════════════════════════════════════════════════
create or replace function public.open_venue_tab(p_venue_id uuid)
returns table (tab_id uuid, join_code text)
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := auth.uid();
  v_existing public.venue_tabs;
  v_code text;
begin
  if v_me is null then raise exception 'not_authenticated'; end if;

  -- Reabrir la que ya está abierta en vez de fallar: el usuario que toca dos
  -- veces "abrir cuenta" quiere su cuenta, no un error.
  select * into v_existing from public.venue_tabs
   where owner_id = v_me and venue_id = p_venue_id and status = 'open' limit 1;
  if found then
    return query select v_existing.id, v_existing.join_code;
    return;
  end if;

  -- Sin vocales: no puede salir una palabra ofensiva ni confundirse 0/O, 1/I.
  loop
    v_code := upper(substr(replace(replace(encode(gen_random_bytes(8), 'base64'), '/', ''), '+', ''), 1, 6));
    v_code := translate(v_code, 'AEIOU01', 'XYZWKRT');
    exit when not exists (select 1 from public.venue_tabs t where t.join_code = v_code);
  end loop;

  insert into public.venue_tabs (venue_id, owner_id, join_code)
  values (p_venue_id, v_me, v_code)
  returning id into tab_id;

  insert into public.venue_tab_members (tab_id, user_id) values (tab_id, v_me);
  join_code := v_code;
  return next;
end;
$$;

create or replace function public.join_venue_tab(p_join_code text)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := auth.uid();
  v_tab public.venue_tabs;
begin
  if v_me is null then raise exception 'not_authenticated'; end if;
  select * into v_tab from public.venue_tabs
   where join_code = upper(btrim(p_join_code)) and status = 'open';
  if not found then raise exception 'tab_not_found'; end if;

  insert into public.venue_tab_members (tab_id, user_id) values (v_tab.id, v_me)
  on conflict (tab_id, user_id) do update set left_at = null;
  return v_tab.id;
end;
$$;

-- ═══════════════════════════════════════════════════════════════════
-- 7. EL CÓDIGO QUE SE MUESTRA EN LA BARRA
-- ═══════════════════════════════════════════════════════════════════
create or replace function public.issue_tab_scan_token(p_tab_id uuid, p_max_amount numeric)
returns table (token text, expires_at timestamptz)
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := auth.uid();
  v_token text;
begin
  if v_me is null then raise exception 'not_authenticated'; end if;
  if not public.bp_is_tab_member(p_tab_id, v_me) then raise exception 'not_a_member'; end if;
  if p_max_amount is null or p_max_amount <= 0 or p_max_amount > 1000 then
    raise exception 'invalid_max_amount';
  end if;
  if not exists (select 1 from public.venue_tabs t where t.id = p_tab_id and t.status = 'open') then
    raise exception 'tab_closed';
  end if;

  -- Los códigos viejos de esta persona en esta cuenta mueren al emitir uno
  -- nuevo: una pantalla que se dejó abierta hace media hora no debería poder
  -- cobrar nada.
  update public.venue_tab_scan_tokens
     set expires_at = now()
   where tab_id = p_tab_id and user_id = v_me and used_at is null and expires_at > now();

  v_token := encode(gen_random_bytes(24), 'hex');
  -- Tres minutos: lo que tarda un bartender en llegar a vos, no lo que tarda
  -- alguien en fotografiarte la pantalla y usarlo después.
  insert into public.venue_tab_scan_tokens (token, tab_id, user_id, max_amount, expires_at)
  values (v_token, p_tab_id, v_me, p_max_amount, now() + interval '3 minutes');

  token := v_token;
  expires_at := now() + interval '3 minutes';
  return next;
end;
$$;

-- ═══════════════════════════════════════════════════════════════════
-- 8. EL COBRO — atómico, idempotente, y nunca deja saldo negativo
-- ═══════════════════════════════════════════════════════════════════
create or replace function public.charge_venue_tab(
  p_token           text,
  p_venue_id        uuid,
  p_amount          numeric,
  p_description     text,
  p_items           jsonb,
  p_idempotency_key text
)
returns table (charge_id uuid, member_id uuid, amount numeric, remaining_balance numeric)
language plpgsql security definer set search_path = public as $$
declare
  v_tok public.venue_tab_scan_tokens;
  v_tab public.venue_tabs;
  v_existing public.venue_tab_charges;
  v_tx uuid;
  v_balance numeric;
  v_charge uuid;
begin
  -- Idempotencia primero: el reintento de un cobro que ya entró devuelve el
  -- mismo cobro, no uno nuevo. Esto es lo que hace segura una barra con mala
  -- señal.
  select * into v_existing from public.venue_tab_charges where idempotency_key = p_idempotency_key;
  if found then
    select w.balance into v_balance from public.wallet_balances w where w.user_id = v_existing.member_id;
    return query select v_existing.id, v_existing.member_id, v_existing.amount, coalesce(v_balance, 0);
    return;
  end if;

  -- El token se bloquea: dos escaneos simultáneos del mismo código no pueden
  -- cobrar dos veces.
  select * into v_tok from public.venue_tab_scan_tokens where token = p_token for update;
  if not found then raise exception 'token_not_found'; end if;
  if v_tok.used_at is not null then raise exception 'token_already_used'; end if;
  if v_tok.expires_at <= now() then raise exception 'token_expired'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'invalid_amount'; end if;
  if p_amount > v_tok.max_amount then raise exception 'amount_above_approved_limit'; end if;

  select * into v_tab from public.venue_tabs where id = v_tok.tab_id;
  if v_tab.status <> 'open' then raise exception 'tab_closed'; end if;
  -- Un local sólo cobra contra su propia cuenta: sin esto, el secreto de un
  -- bar sirve para cobrar en otro.
  if v_tab.venue_id <> p_venue_id then raise exception 'wrong_venue'; end if;

  -- Debita la billetera de quien consumió. adjust_wallet_balance levanta
  -- insufficient_funds ANTES de comitear, así que un saldo corto no deja la
  -- cuenta a medio cobrar.
  select t.transaction_id, t.balance into v_tx, v_balance
    from public.adjust_wallet_balance(v_tok.user_id, -p_amount, 'spend') t;

  insert into public.venue_tab_charges
    (tab_id, member_id, venue_id, description, items, amount, wallet_transaction_id, idempotency_key)
  values
    (v_tab.id, v_tok.user_id, p_venue_id, p_description, coalesce(p_items, '[]'::jsonb), p_amount, v_tx, p_idempotency_key)
  returning id into v_charge;

  update public.venue_tab_scan_tokens
     set used_at = now(), used_by_charge = v_charge
   where token = p_token;

  return query select v_charge, v_tok.user_id, p_amount, v_balance;
end;
$$;

-- ═══════════════════════════════════════════════════════════════════
-- 9. CERRAR
-- ═══════════════════════════════════════════════════════════════════
-- Cerrar no cobra nada: cada consumo ya se pagó en el momento. Cerrar sólo
-- deja de aceptar cobros nuevos, que es lo que querés cuando te vas.
create or replace function public.close_venue_tab(p_tab_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare v_me uuid := auth.uid();
begin
  if v_me is null then raise exception 'not_authenticated'; end if;
  if not exists (select 1 from public.venue_tabs t where t.id = p_tab_id and t.owner_id = v_me) then
    raise exception 'not_the_owner';
  end if;
  update public.venue_tabs set status = 'closed', closed_at = now()
   where id = p_tab_id and status = 'open';
  update public.venue_tab_scan_tokens set expires_at = now()
   where tab_id = p_tab_id and used_at is null and expires_at > now();
end;
$$;

-- ═══════════════════════════════════════════════════════════════════
-- 10. PERMISOS
-- ═══════════════════════════════════════════════════════════════════
revoke all on function public.open_venue_tab(uuid)                     from public, anon;
revoke all on function public.join_venue_tab(text)                     from public, anon;
revoke all on function public.issue_tab_scan_token(uuid, numeric)      from public, anon;
revoke all on function public.close_venue_tab(uuid)                    from public, anon;
-- El cobro NO lo puede llamar un cliente, ni siquiera logueado: entra sólo
-- por /api/venue/tab/charge, que además exige el x-venue-secret del local.
revoke all on function public.charge_venue_tab(text, uuid, numeric, text, jsonb, text) from public, anon, authenticated;

grant execute on function public.open_venue_tab(uuid)                to authenticated;
grant execute on function public.join_venue_tab(text)                to authenticated;
grant execute on function public.issue_tab_scan_token(uuid, numeric) to authenticated;
grant execute on function public.close_venue_tab(uuid)               to authenticated;
grant select on public.venue_tabs, public.venue_tab_members, public.venue_tab_charges to authenticated;
