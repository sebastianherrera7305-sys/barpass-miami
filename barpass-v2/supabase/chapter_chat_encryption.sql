-- Encrypts chapter_messages content at rest (pgcrypto AES, symmetric key
-- held in Supabase Vault — never in application code, never sent to any
-- client, never queryable via PostgREST).
--
-- This is encryption AT REST, not end-to-end: the key lives in the
-- database and send_chapter_message()/get_chapter_messages() (both
-- SECURITY DEFINER, running as the DB itself) can decrypt. That's a
-- deliberate tradeoff, not an oversight — report_chapter_message()'s
-- auto-hide-at-3-reports moderation and the archive-on-delete trail both
-- require server-side content inspection; true E2EE would make that
-- impossible without a much bigger redesign (per-recipient key envelopes,
-- no server-side moderation at all). What this DOES close: a DB dump, a
-- misconfigured RLS policy, or a leaked service-role key no longer hands
-- over chat content in plaintext — today it's a bare `text` column
-- anyone with DB access can read directly.
--
-- Run once, after chapter_chat.sql. Idempotent — safe to re-run.

create extension if not exists pgcrypto;
create extension if not exists supabase_vault cascade;

do $$
begin
  if not exists (select 1 from vault.secrets where name = 'chapter_chat_key') then
    perform vault.create_secret(encode(gen_random_bytes(32), 'base64'), 'chapter_chat_key');
  end if;
end $$;

alter table public.chapter_messages add column if not exists text_enc bytea;
alter table public.chapter_messages alter column text drop not null;
alter table public.chapter_messages_archive add column if not exists text_enc bytea;

-- Backfill: encrypt every existing plaintext row, then scrub the plaintext.
-- The whole point of "at rest" is that the plaintext copy doesn't survive
-- this migration, not just that new rows are encrypted going forward.
do $$
declare v_key text;
begin
  select decrypted_secret into v_key from vault.decrypted_secrets where name = 'chapter_chat_key';
  update public.chapter_messages
    set text_enc = pgp_sym_encrypt(text, v_key)
    where text_enc is null and text is not null;
  update public.chapter_messages set text = null where text_enc is not null;

  update public.chapter_messages_archive
    set text_enc = pgp_sym_encrypt(text, v_key)
    where text_enc is null and text is not null;
  update public.chapter_messages_archive set text = null where text_enc is not null;
end $$;

-- send_chapter_message: writes ciphertext only now. Same affiliation/ban/
-- rate-limit checks as before — the length check moves from the column's
-- CHECK constraint (which can't see plaintext length once it's `text_enc`)
-- into the function itself.
create or replace function public.send_chapter_message(p_text text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_chapter_id uuid;
  v_recent_count int;
  v_message_id uuid;
  v_key text;
begin
  if char_length(p_text) = 0 or char_length(p_text) > 1000 then
    raise exception 'message must be 1-1000 characters';
  end if;

  select chapter_id into v_chapter_id from profiles where id = auth.uid();
  if v_chapter_id is null then
    raise exception 'no chapter affiliation set';
  end if;
  if exists (
    select 1 from chapter_bans
    where chapter_id = v_chapter_id and user_id = auth.uid()
      and (expires_at is null or expires_at > now())
  ) then
    raise exception 'banned from this chapter chat';
  end if;
  select count(*) into v_recent_count from chapter_messages
    where user_id = auth.uid() and created_at > now() - interval '5 minutes';
  if v_recent_count >= 10 then
    raise exception 'rate limit exceeded';
  end if;

  select decrypted_secret into v_key from vault.decrypted_secrets where name = 'chapter_chat_key';
  insert into chapter_messages (chapter_id, user_id, text_enc)
    values (v_chapter_id, auth.uid(), pgp_sym_encrypt(p_text, v_key))
    returning id into v_message_id;
  return v_message_id;
end;
$$;

-- New read path — PostgREST can no longer serve usable content by
-- selecting the table directly (text is null, text_enc is opaque bytes),
-- so reads go through this RPC. Same membership/ban/deleted_at gating the
-- old "view chapter messages" RLS policy did, just re-expressed as
-- application logic so it can decrypt too. Returns oldest-first, capped,
-- to match what the client already expects.
create or replace function public.get_chapter_messages(p_limit int default 200) returns table (
  id uuid, chapter_id uuid, user_id uuid, text text, created_at timestamptz, is_system boolean
)
language plpgsql security definer set search_path = public as $$
declare
  v_chapter_id uuid;
  v_key text;
begin
  -- Qualified as profiles.chapter_id / profiles.id — this function's own
  -- RETURNS TABLE declares both `id` and `chapter_id` output columns, so
  -- PL/pgSQL turns them into implicit variables in scope here. A bare
  -- reference to either (the pattern every other function in this schema
  -- uses safely, since none of the others return columns with these exact
  -- names) is ambiguous: "column reference chapter_id is ambiguous... could
  -- refer to either a PL/pgSQL variable or a table column." This broke
  -- every chat load from the moment this function shipped.
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

  select decrypted_secret into v_key from vault.decrypted_secrets where name = 'chapter_chat_key';
  return query
    select sub.id, sub.chapter_id, sub.user_id, sub.text, sub.created_at, sub.is_system
    from (
      select m.id, m.chapter_id, m.user_id,
             pgp_sym_decrypt(m.text_enc, v_key) as text,
             m.created_at, m.is_system
      from chapter_messages m
      where m.chapter_id = v_chapter_id and m.deleted_at is null
      order by m.created_at desc
      limit greatest(least(p_limit, 500), 1)
    ) sub
    order by sub.created_at asc;
end;
$$;

revoke execute on function public.send_chapter_message(text) from public, anon;
grant execute on function public.send_chapter_message(text) to authenticated;
revoke execute on function public.get_chapter_messages(int) from public, anon;
grant execute on function public.get_chapter_messages(int) to authenticated;

-- archive_hidden_chapter_message: carries the ciphertext forward instead
-- of plaintext — the accountability trail stays intact, still encrypted.
create or replace function public.archive_hidden_chapter_message() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.deleted_at is not null and old.deleted_at is null then
    insert into chapter_messages_archive
      (original_message_id, chapter_id, user_id, text_enc, created_at, deleted_at, deleted_by, report_count, archive_reason)
    values
      (new.id, new.chapter_id, new.user_id, new.text_enc, new.created_at, new.deleted_at, new.deleted_by,
       new.report_count, case when new.report_count >= 3 then 'auto_hidden_reports' else 'manual_delete' end);
  end if;
  return new;
end;
$$;
