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
create or replace function can_purchase_student_ticket(p_event_id uuid, p_user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile profiles%rowtype;
  v_event events%rowtype;
  v_tickets_bought int;
begin
  select * into v_profile from profiles where id = p_user_id;
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
  where customer_id = p_user_id and event_id = p_event_id;

  if v_tickets_bought >= v_event.max_tickets_per_student then
    return false;
  end if;

  return true;
end;
$$;
