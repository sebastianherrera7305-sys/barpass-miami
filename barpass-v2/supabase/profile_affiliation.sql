-- Real, self-declared affiliation to a university + Greek chapter from the
-- verified directory (greek_life_schema.sql). Self-declared, not
-- cryptographically verified — a user can pick any chapter, we don't check
-- real-world membership. Both nullable: affiliation is optional.
--
-- Idempotent, safe to re-run.

alter table public.profiles
  add column if not exists university_id uuid references public.universities(id),
  add column if not exists chapter_id uuid references public.greek_chapters(id);
