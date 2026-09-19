-- ─────────────────────────────────────────────────────────────────────────
-- BarPass V2 — CHAT WAS BROKEN: pgcrypto is not on the functions' search_path.
--
-- Run in the Supabase SQL editor. Idempotent — safe to re-run.
--
-- Symptom, verified live 2026-09-15 with a real signed-in test account in a
-- real chapter:
--     get_chapter_messages  -> 42883 function pgp_sym_decrypt(bytea, text) does not exist
--     send_chapter_message  -> 42883 function pgp_sym_encrypt(text, text) does not exist
-- So chapter chat has never been able to send or read a single message since
-- encryption was added. The same defect is in the friend chat shipped today,
-- because it copied the working pattern — which was not working.
--
-- Cause: on Supabase, `create extension if not exists pgcrypto` installs into
-- the **extensions** schema, not public. Every one of these functions is
-- declared `security definer set search_path = public`, which is correct and
-- deliberate (an unpinned search_path on a SECURITY DEFINER function is a
-- privilege-escalation hole) — but it also means pgp_sym_encrypt/decrypt are
-- simply not visible inside them.
--
-- Fix: keep the pinned search_path, and ADD the schema pgcrypto actually
-- lives in. `public, extensions` stays pinned — it does not reintroduce the
-- escalation risk, because both schemas are fixed and non-user-writable.
-- ─────────────────────────────────────────────────────────────────────────

-- Make sure it exists somewhere sane. On a project where it is already in
-- `extensions`, this is a no-op; on one where it is in public, the ALTER
-- below still resolves it because public stays on the path.
create extension if not exists pgcrypto with schema extensions;

do $$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as sig
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in (
         'send_chapter_message', 'get_chapter_messages',
         'send_friend_message',  'get_friend_messages',
         'list_friend_threads'
       )
  loop
    execute format('alter function %s set search_path = public, extensions', r.sig);
    raise notice 'search_path fixed: %', r.sig;
  end loop;
end $$;

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════
--
-- pgcrypto is reachable and round-trips.            -- expect: hello
--   select extensions.pgp_sym_decrypt(
--            extensions.pgp_sym_encrypt('hello', 'k'), 'k');
--
-- Which schema is it actually in?                   -- expect: extensions
--   select n.nspname from pg_extension e
--     join pg_namespace n on n.oid = e.extnamespace where e.extname = 'pgcrypto';
--
-- Every chat function now carries both schemas.     -- expect 5 rows, each
--                                                   -- showing {search_path=public, extensions}
--   select p.proname, p.proconfig
--     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'public'
--      and p.proname in ('send_chapter_message','get_chapter_messages',
--                        'send_friend_message','get_friend_messages',
--                        'list_friend_threads');
--
-- And the vault key the functions read must exist.  -- expect 1 row each
--   select name from vault.decrypted_secrets
--    where name in ('chapter_chat_key','friend_chat_key');
