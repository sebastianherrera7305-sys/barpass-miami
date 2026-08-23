-- Text-only chat scoped to one Greek chapter. Only members who declared that
-- chapter as their affiliation (profiles.chapter_id) can read or post — the
-- RLS policy and the RPC both check it server-side, never trusting the
-- client. Rate-limited (10 msg/5min) and report+auto-hide-at-3 moderated.
--
-- Idempotent, safe to re-run.

create table if not exists public.chapter_messages (
  id uuid primary key default gen_random_uuid(),
  chapter_id uuid references public.greek_chapters(id) not null,
  user_id uuid references public.profiles(id),
  text text not null check (char_length(text) <= 1000),
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  deleted_by uuid references public.profiles(id),
  report_count int not null default 0,
  is_system boolean not null default false
);

-- unique(message_id, reporter_id) is load-bearing: without it, one user
-- filing the same report 3x would auto-hide a message on their own.
create table if not exists public.chapter_message_reports (
  id uuid primary key default gen_random_uuid(),
  message_id uuid references public.chapter_messages(id) on delete cascade,
  reporter_id uuid references public.profiles(id),
  reason text not null,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references public.profiles(id),
  action text check (action in ('dismissed', 'message_hidden', 'user_banned')),
  unique(message_id, reporter_id)
);

-- Snapshot of a message at the moment it's removed (auto-hide or manual
-- delete) — kept for moderation accountability, never shown to end users.
create table if not exists public.chapter_messages_archive (
  id uuid primary key default gen_random_uuid(),
  original_message_id uuid not null,
  chapter_id uuid references public.greek_chapters(id),
  user_id uuid references public.profiles(id),
  text text,
  created_at timestamptz,
  deleted_at timestamptz,
  deleted_by uuid references public.profiles(id),
  report_count int,
  archived_at timestamptz not null default now(),
  archive_reason text
);

create table if not exists public.chapter_bans (
  id uuid primary key default gen_random_uuid(),
  chapter_id uuid references public.greek_chapters(id),
  user_id uuid references public.profiles(id),
  banned_by uuid references public.profiles(id),
  reason text,
  banned_at timestamptz not null default now(),
  expires_at timestamptz,
  unique(chapter_id, user_id)
);

alter table public.chapter_messages enable row level security;
alter table public.chapter_message_reports enable row level security;
alter table public.chapter_messages_archive enable row level security;
alter table public.chapter_bans enable row level security;
-- No select/insert/update policy on the archive for anon/authenticated —
-- it's written only by the trigger below (SECURITY DEFINER) and read only
-- via the service-role key (admin tooling), same convention as other
-- moderation-only tables in this project.

drop policy if exists "view chapter messages" on public.chapter_messages;
create policy "view chapter messages" on public.chapter_messages for select
  to authenticated
  using (
    chapter_id = (select chapter_id from public.profiles where id = auth.uid())
    and deleted_at is null
    and not exists (
      select 1 from public.chapter_bans
      where chapter_id = chapter_messages.chapter_id and user_id = auth.uid()
        and (expires_at is null or expires_at > now())
    )
  );

drop policy if exists "report a message" on public.chapter_message_reports;
create policy "report a message" on public.chapter_message_reports for insert
  to authenticated
  with check (reporter_id = auth.uid());

create or replace function public.send_chapter_message(p_text text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_chapter_id uuid;
  v_recent_count int;
  v_message_id uuid;
begin
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
  insert into chapter_messages (chapter_id, user_id, text)
    values (v_chapter_id, auth.uid(), p_text)
    returning id into v_message_id;
  return v_message_id;
end;
$$;

create or replace function public.report_chapter_message(p_message_id uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into chapter_message_reports (message_id, reporter_id, reason)
    values (p_message_id, auth.uid(), p_reason)
    on conflict (message_id, reporter_id) do nothing;
  update chapter_messages
    set report_count = (select count(*) from chapter_message_reports where message_id = p_message_id)
    where id = p_message_id;
  if (select report_count from chapter_messages where id = p_message_id) >= 3 then
    update chapter_messages set deleted_at = now() where id = p_message_id and deleted_at is null;
    update chapter_message_reports set resolved_at = now(), action = 'message_hidden'
      where message_id = p_message_id and resolved_at is null;
  end if;
end;
$$;

-- Snapshots a message into the archive the instant it gets a deleted_at
-- (auto-hide via report_chapter_message, or a future manual-delete path) —
-- never mutates chapter_messages.text itself, so the live table stays a
-- clean "what's visible now" view.
create or replace function public.archive_hidden_chapter_message() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.deleted_at is not null and old.deleted_at is null then
    insert into chapter_messages_archive
      (original_message_id, chapter_id, user_id, text, created_at, deleted_at, deleted_by, report_count, archive_reason)
    values
      (new.id, new.chapter_id, new.user_id, new.text, new.created_at, new.deleted_at, new.deleted_by,
       new.report_count, case when new.report_count >= 3 then 'auto_hidden_reports' else 'manual_delete' end);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_archive_hidden_chapter_message on public.chapter_messages;
create trigger trg_archive_hidden_chapter_message
  after update of deleted_at on public.chapter_messages
  for each row execute function public.archive_hidden_chapter_message();

revoke execute on function public.send_chapter_message(text) from public, anon;
grant execute on function public.send_chapter_message(text) to authenticated;
revoke execute on function public.report_chapter_message(uuid, text) from public, anon;
grant execute on function public.report_chapter_message(uuid, text) to authenticated;

create index if not exists chapter_messages_chapter_idx on public.chapter_messages (chapter_id, created_at);
