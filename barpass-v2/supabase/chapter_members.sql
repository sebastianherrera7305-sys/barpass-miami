-- Member roster for a chapter — visible only to that chapter's own members
-- (self-declared affiliation via profiles.chapter_id, same "accepted into
-- the chapter" gate chat/events already use — there's no separate
-- verification/admission step in this app yet, just the honest state that
-- exists: profiles.chapter_id set = you've marked this chapter as yours).
--
-- Deliberately returns only what a member already shares elsewhere in the
-- app (display name, level/points, join date) — never email, never
-- birthdate/home address, nothing from the other privacy-sensitive columns
-- on profiles. Idempotent.

create or replace function public.list_chapter_members()
returns table (
  id uuid, display_name text, bpx_points int, joined_at timestamptz
)
language plpgsql security definer set search_path = public as $$
declare
  v_chapter_id uuid;
begin
  select profiles.chapter_id into v_chapter_id from profiles where profiles.id = auth.uid();
  if v_chapter_id is null then
    return;
  end if;
  if exists (
    select 1 from chapter_bans
    where chapter_bans.chapter_id = v_chapter_id and chapter_bans.user_id = auth.uid()
      and (chapter_bans.expires_at is null or chapter_bans.expires_at > now())
  ) then
    return;
  end if;

  return query
    select p.id, coalesce(nullif(trim(p.display_name), ''), 'Nightlifer'), p.bpx_points, p.created_at
    from profiles p
    where p.chapter_id = v_chapter_id
    order by p.created_at asc;
end;
$$;

revoke execute on function public.list_chapter_members() from public, anon;
grant execute on function public.list_chapter_members() to authenticated;
