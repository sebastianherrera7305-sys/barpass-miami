-- BarPass Student Network — Fase 1
-- Extiende tablas existentes en vez de crear un segundo sistema paralelo.
-- Ya existen: universities (47 filas), greek_chapters (1449 filas),
-- profiles.university_id / profiles.chapter_id.
--
-- Corrección sobre la propuesta original de Kimi: el precio real vive en
-- events.cover_price (no en passes — passes es el ticket YA emitido, no
-- un catálogo). Y orders/passes no tenían event_id, así que "cuántos
-- tickets de estudiante compró este usuario para este evento" no se
-- podía calcular — se agrega acá.

-- 1. Verificación de estudiante en el perfil existente (no una tabla nueva)
alter table profiles add column if not exists student_verified boolean not null default false;
alter table profiles add column if not exists student_verified_at timestamptz;
alter table profiles add column if not exists student_verification_expires timestamptz;
alter table profiles add column if not exists student_verification_method text
  check (student_verification_method in ('self_declared', 'email', 'sso', 'manual_review'));

-- self_declared = MVP actual (el usuario ya elige su university_id/chapter_id
-- en el perfil). No se agrega student_id, imagen de carnet, GPA ni ningún
-- dato académico — solo el resultado de la verificación.

-- profiles' "update own profile" policy (schema.sql) is `using (auth.uid() =
-- id)` with no column restriction and no WITH CHECK — same shape that
-- required protect_profile_points() for bpx_points. Unlike bpx_points,
-- self-declaration here is intentional (a user IS meant to be able to flip
-- student_verified on their own row), so this can't just pin the column
-- back like that trigger does. What it must not allow is escalation past
-- self-declaration: claiming a stronger method ('email'/'sso'/
-- 'manual_review') the user never actually went through, or setting an
-- expiry far in the future to keep student pricing indefinitely. Any client
-- update touching these columns is forced back to the one shape a real
-- self-declaration produces; a future real verification flow (email/SSO/
-- manual review) must go through a SECURITY DEFINER RPC instead of a direct
-- client PATCH, same pattern as adjust_wallet_balance.
create or replace function public.protect_student_verification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.student_verified is distinct from old.student_verified
     or new.student_verification_method is distinct from old.student_verification_method
     or new.student_verification_expires is distinct from old.student_verification_expires then
    if new.student_verified is true then
      new.student_verification_method := 'self_declared';
      new.student_verified_at := now();
      new.student_verification_expires := now() + interval '1 year';
    else
      new.student_verification_method := null;
      new.student_verified_at := null;
      new.student_verification_expires := null;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists protect_student_verification_trigger on public.profiles;
create trigger protect_student_verification_trigger
  before update on public.profiles
  for each row
  execute function public.protect_student_verification();

-- 2. Precio y elegibilidad de estudiante en el evento real (events.cover_price
-- ya existe — esto es adicional, no reemplaza el precio normal)
alter table events add column if not exists student_eligible boolean not null default false;
alter table events add column if not exists student_price_cents int;
alter table events add column if not exists max_tickets_per_student int not null default 4;

-- 3. El gap real: passes no tenía forma de saber a qué evento pertenece
-- un ticket ya emitido. Sin esto, "cuántos tickets de este evento ya
-- compró este usuario" es imposible de calcular.
alter table passes add column if not exists event_id uuid references events(id);

-- 4. Eligibility check — reescrito contra el schema real (no
-- orders.items->>'pass_id', que no existe: orders.items está vacío en
-- toda la data real hoy).
--
-- Originally took p_user_id as a second argument and trusted it — any
-- authenticated caller could pass a stranger's uuid and learn whether that
-- specific person is a currently-eligible verified student for a given
-- event (a real, if narrow, privacy leak: student_verified/expiry status
-- exposed for any user by guessing/enumerating ids). Zero callers ever
-- shipped against that signature, so this drops the old overload rather
-- than versioning around it, and the function now only ever checks the
-- caller's own auth.uid() — the same "never trust an id the client hands
-- you" rule every other SECURITY DEFINER function in this schema follows.
drop function if exists can_purchase_student_ticket(uuid, uuid);

create or replace function can_purchase_student_ticket(p_event_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile profiles%rowtype;
  v_event events%rowtype;
  v_tickets_bought int;
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    return false;
  end if;
  select * into v_profile from profiles where id = v_user_id;
  select * into v_event from events where id = p_event_id;

  if v_profile.id is null or v_event.id is null then
    return false;
  end if;

  -- ¿Es un evento con precio de estudiante habilitado?
  if not v_event.student_eligible then
    return false;
  end if;

  -- ¿El usuario está verificado como estudiante? (nunca implica 21+ —
  -- eso es un campo totalmente separado, ver age_policy en venues)
  if not v_profile.student_verified then
    return false;
  end if;

  -- ¿La verificación no venció?
  if v_profile.student_verification_expires is not null
     and v_profile.student_verification_expires < now() then
    return false;
  end if;

  -- ¿No excedió el límite de tickets por estudiante para este evento?
  select count(*) into v_tickets_bought
  from passes
  where customer_id = v_user_id and event_id = p_event_id;

  if v_tickets_bought >= v_event.max_tickets_per_student then
    return false;
  end if;

  return true;
end;
$$;

revoke execute on function can_purchase_student_ticket(uuid) from public, anon;
grant execute on function can_purchase_student_ticket(uuid) to authenticated;
