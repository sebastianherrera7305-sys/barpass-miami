-- Enhances check_in_venue() from the_grid.sql with real product behavior
-- Kimi proposed (good ideas, reconciled against the existing RPCs instead
-- of duplicated as new ones with a different name):
--  - checking into a new venue auto-closes any other still-open checkin —
--    a user can't be "at" two venues at once.
--  - re-checking into the SAME venue while already checked in is
--    idempotent (returns the existing row instead of erroring/duplicating).
--  - a new get_active_checkin() so the UI can ask "where am I right now"
--    without a raw table read (RLS already scopes venue_checkins to the
--    owner, but this keeps the read path RPC-shaped and consistent).
--
-- Rejected from Kimi's version: an RLS "update own checkins" policy —
-- that would let a client UPDATE their own row directly, bypassing the
-- RPC entirely and defeating the whole point of computing age_at_checkin
-- server-side. venue_checkins keeps NO client insert/update policy, same
-- as the_grid.sql. security definer + search_path pinning kept throughout.
--
-- Idempotent, safe to re-run.

create or replace function public.check_in_venue(p_venue_id uuid, p_trip_id uuid default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_birthdate date;
  v_age int;
  v_chapter_id uuid;
  v_existing_id uuid;
  v_checkin_id uuid;
begin
  select birthdate, chapter_id into v_birthdate, v_chapter_id from profiles where id = auth.uid();
  if v_birthdate is null then
    raise exception 'birthdate required before check-in';
  end if;
  v_age := extract(year from age(v_birthdate));
  if v_age < 18 then
    raise exception 'must be 18+ to check in';
  end if;

  -- Close any other still-open checkin first — a user is at one venue at a time.
  update venue_checkins set checked_out_at = now()
    where user_id = auth.uid() and checked_out_at is null and venue_id != p_venue_id;

  -- Re-checking into the same venue is idempotent, not a duplicate row.
  select id into v_existing_id from venue_checkins
    where user_id = auth.uid() and venue_id = p_venue_id and checked_out_at is null;
  if v_existing_id is not null then
    return v_existing_id;
  end if;

  insert into venue_checkins (user_id, venue_id, trip_id, chapter_id, age_at_checkin)
    values (auth.uid(), p_venue_id, p_trip_id, v_chapter_id, v_age)
    returning id into v_checkin_id;
  return v_checkin_id;
end;
$$;

create or replace function public.get_active_checkin() returns table (
  checkin_id uuid, venue_id uuid, checked_in_at timestamptz
)
language plpgsql security definer set search_path = public as $$
begin
  return query
  select vc.id, vc.venue_id, vc.checked_in_at
  from venue_checkins vc
  where vc.user_id = auth.uid() and vc.checked_out_at is null
  limit 1;
end;
$$;

revoke execute on function public.get_active_checkin() from public, anon;
grant execute on function public.get_active_checkin() to authenticated;
