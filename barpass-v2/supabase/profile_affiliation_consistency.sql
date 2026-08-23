-- `profiles.university_id` and `profiles.chapter_id` are two independent FKs
-- with no constraint tying them together — a raw API write (bypassing the
-- app's own picker, which only ever offers a chapter that belongs to the
-- selected university) could set university_id = University A while
-- chapter_id points at a chapter that actually belongs to University B. The
-- app UI never does this, but the database itself should refuse it too.
--
-- Idempotent, safe to re-run.

create or replace function public.check_profile_affiliation_consistency()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.chapter_id is not null and new.university_id is not null then
    if not exists (
      select 1 from public.greek_chapters
      where id = new.chapter_id and university_id = new.university_id
    ) then
      raise exception 'chapter_id % does not belong to university_id %', new.chapter_id, new.university_id;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists profile_affiliation_consistency on public.profiles;
create trigger profile_affiliation_consistency
  before insert or update of university_id, chapter_id on public.profiles
  for each row
  execute function public.check_profile_affiliation_consistency();
