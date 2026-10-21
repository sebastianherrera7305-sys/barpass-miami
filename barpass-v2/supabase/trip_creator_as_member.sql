-- TRIP CHAT bug A — "ya no formas parte de este trip" en el chat del grupo
-- que acabo de crear (TestFlight Build 128).
--
-- La RLS de `trip_messages` y las dos RPCs (`get_trip_messages`,
-- `send_trip_message`) deciden pertenencia así:
--
--     auth.uid() = t.creator_id OR auth.uid() = any(t.member_ids)
--
-- La predicate ya tolera que el creator falte de member_ids. El bug ocurría
-- cuando OTRA vista (TripsListV2View asV2CardModel, GroupNightView.allMemberIds)
-- asumía que creator NO estaba en member_ids: contaban doble, duplicaban
-- avatares, y en algunos paths borraban member_ids al PATCHear la fila
-- entera desde un snapshot cliente que todavía no se había poblado.
--
-- Fix "sin carrera, del lado del servidor" (preferido por el task): un
-- trigger BEFORE INSERT que GARANTIZA que creator_id siempre quede dentro
-- de member_ids antes de que la fila toque RLS. El cliente puede olvidarse
-- del paso y ya no hay forma de insertar una fila inconsistente.
--
-- Idempotente, safe to re-run. Requiere: trips_schema.sql.

create or replace function public.trips_ensure_creator_in_members()
returns trigger
language plpgsql
as $$
begin
    -- Normaliza: si member_ids no incluye al creator, lo pone en la
    -- posición 0 (misma convención que TripStore.create en el cliente).
    if new.member_ids is null then
        new.member_ids := array[new.creator_id];
    elsif not (new.creator_id = any(new.member_ids)) then
        new.member_ids := array[new.creator_id] || new.member_ids;
    end if;
    return new;
end;
$$;

drop trigger if exists trips_ensure_creator_in_members on public.trips;
create trigger trips_ensure_creator_in_members
    before insert on public.trips
    for each row execute function public.trips_ensure_creator_in_members();

-- También corregir las filas históricas que puedan tener el creator fuera
-- de member_ids (p.ej. trips creados con un cliente viejo antes de que
-- TripStore.create ensamblara el array). One-shot, idempotente.
update public.trips
set member_ids = array[creator_id] || coalesce(member_ids, '{}')
where member_ids is null or not (creator_id = any(member_ids));
