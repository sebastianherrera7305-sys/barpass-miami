-- Nombres reales de los integrantes de un trip.
--
-- POR QUÉ EXISTE: `profiles` sólo tiene la policy "read own profile"
-- (schema.sql:82) — ningún usuario puede leer el display_name de otro,
-- nunca. Por eso TripDetailView venía mostrando el UUID crudo de cada
-- miembro en lugar de su nombre, y por eso el beacon no podía decir
-- "Ana te está buscando": el cliente no tiene de dónde sacar "Ana".
--
-- Mismo patrón que list_chapter_members(): security definer, el alcance lo
-- fija el servidor a partir de auth.uid(), y devuelve SÓLO lo que esa
-- persona ya comparte con el grupo (nombre). Nada de email, birthdate,
-- home_address ni puntos.
--
-- El trip lo elige el llamador, pero la pertenencia la verifica el servidor:
-- si no sos miembro, devuelve vacío. Idempotente.

create or replace function public.list_trip_members(p_trip_id uuid)
returns table (id uuid, display_name text)
language plpgsql security definer set search_path = public as $$
declare
  v_members uuid[];
begin
  select array_append(t.member_ids, t.creator_id) into v_members
  from trips t
  where t.id = p_trip_id
    and (auth.uid() = t.creator_id or auth.uid() = any(t.member_ids));

  if v_members is null then
    return;  -- el trip no existe, o el que pregunta no es del grupo
  end if;

  return query
    select p.id, coalesce(nullif(trim(p.display_name), ''), 'Nightlifer')
    from profiles p
    where p.id = any(v_members);
end;
$$;

revoke execute on function public.list_trip_members(uuid) from public, anon;
grant execute on function public.list_trip_members(uuid) to authenticated;
