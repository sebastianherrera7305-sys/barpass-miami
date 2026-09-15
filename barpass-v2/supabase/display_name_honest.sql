-- ─────────────────────────────────────────────────────────────────────────
-- BarPass V2 — STOP STORING A PLACEHOLDER AS IF IT WERE A NAME.
--
-- Run in the Supabase SQL editor. Idempotent — safe to re-run.
--
-- schema.sql's signup trigger does:
--     coalesce(new.raw_user_meta_data->>'name', 'Nightlifer')
-- so anyone who signs up without a name gets the literal string 'Nightlifer'
-- WRITTEN INTO the row. 10 of 11 profiles today are called 'Nightlifer'.
--
-- That is indistinguishable from someone genuinely named that, and it breaks
-- the feature that needs names most: friend search returns ten identical
-- people with no way to tell them apart. It also means nothing can ever ask
-- "has this user set a name?", because the answer is always yes.
--
-- The fix is the same rule this project already applies to venue data: an
-- empty value is a fact, a guessed one is a lie. Store NULL when there is no
-- name. Every reader already coalesces to 'Nightlifer' for DISPLAY
-- (chapter_members.sql, host_events_schema.sql), so nothing renders blank —
-- the placeholder stays where it belongs, in the view layer.
-- ─────────────────────────────────────────────────────────────────────────

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    -- No placeholder. nullif() also catches a signup that sent an empty
    -- string, which would otherwise be a name made of nothing.
    nullif(trim(coalesce(new.raw_user_meta_data->>'name', '')), '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- Existing rows: only the ones that are exactly the placeholder. A real user
-- who deliberately typed "Nightlifer" keeps it — this matches the literal the
-- trigger wrote, and nothing else.
update public.profiles
   set display_name = null
 where display_name = 'Nightlifer';

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════
--
-- How many people have actually chosen a name.
--   select count(*) filter (where display_name is not null) as named,
--          count(*)                                          as total
--     from public.profiles;
--
-- No placeholder is stored any more.               -- expect 0
--   select count(*) from public.profiles where display_name = 'Nightlifer';
--
-- The trigger no longer invents one (read it back).
--   select prosrc from pg_proc where proname = 'handle_new_user';
