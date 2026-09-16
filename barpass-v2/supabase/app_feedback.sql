-- app_feedback — "¿qué podemos hacer mejor?"
--
-- Sits behind the Home Screen quick action shown at the moment someone is
-- about to delete the app. Write-only by design: a person can leave a
-- message, and nobody (not even its author) can read the table back through
-- the API. Read it in the SQL editor.
create table if not exists public.app_feedback (
  id          uuid primary key default gen_random_uuid(),
  -- Null for a guest. ON DELETE SET NULL so "delete my account" doesn't
  -- silently destroy the reason they left.
  user_id     uuid references auth.users(id) on delete set null,
  message     text not null check (char_length(btrim(message)) between 1 and 2000),
  app_version text,
  platform    text not null default 'ios',
  created_at  timestamptz not null default now()
);

alter table public.app_feedback enable row level security;

drop policy if exists "anyone may leave feedback" on public.app_feedback;
create policy "anyone may leave feedback"
  on public.app_feedback for insert
  to anon, authenticated
  with check (
    -- A signed-in writer may only sign their own name to it; a guest leaves
    -- it unsigned. Neither can attribute feedback to someone else.
    user_id is null or user_id = auth.uid()
  );

-- No select policy at all, plus an explicit revoke: feedback is not readable
-- through PostgREST by anyone. (A column REVOKE under a table GRANT is a
-- no-op — see reference-postgres-column-revoke-trap — so revoke the table.)
revoke select on public.app_feedback from anon, authenticated;
grant insert on public.app_feedback to anon, authenticated;

create index if not exists app_feedback_created_idx on public.app_feedback (created_at desc);
