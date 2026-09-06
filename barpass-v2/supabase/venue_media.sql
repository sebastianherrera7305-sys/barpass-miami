-- User-uploaded photos/videos per venue — "Factory Town" (an event venue
-- open only a handful of nights a year) was the trigger: the user wants
-- people at tonight's event to post photos/videos from inside the app.
-- Deliberately simple for a same-day ship: no moderation queue, no
-- approval step — public read, own-row delete, everything else immutable.
--
-- Idempotent, safe to re-run.

create table if not exists public.venue_media (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid references public.venues(id) not null,
  user_id uuid references public.profiles(id) not null,
  media_url text not null,
  media_type text not null check (media_type in ('photo', 'video')),
  created_at timestamptz not null default now()
);

alter table public.venue_media enable row level security;

drop policy if exists "venue media is public" on public.venue_media;
create policy "venue media is public" on public.venue_media for select
  to anon, authenticated
  using (true);

drop policy if exists "authenticated can post venue media" on public.venue_media;
create policy "authenticated can post venue media" on public.venue_media for insert
  to authenticated
  with check (user_id = auth.uid());

drop policy if exists "owner can delete own venue media" on public.venue_media;
create policy "owner can delete own venue media" on public.venue_media for delete
  to authenticated
  using (user_id = auth.uid());

create index if not exists venue_media_venue_idx on public.venue_media (venue_id, created_at desc);

-- Storage bucket for the actual files — run this part in the Supabase
-- dashboard if the SQL editor rejects storage.buckets writes (some
-- projects restrict it): Storage → New bucket → name "venue-media",
-- Public bucket = ON.
insert into storage.buckets (id, name, public)
values ('venue-media', 'venue-media', true)
on conflict (id) do nothing;

-- Anyone can read (bucket is public already, but explicit policy for
-- clarity/defense in depth); only an authenticated user can upload, and
-- only into a path prefixed with their own user id (enforced below) so one
-- user can't overwrite another's files by guessing a path.
drop policy if exists "venue media bucket is public" on storage.objects;
create policy "venue media bucket is public" on storage.objects for select
  to anon, authenticated
  using (bucket_id = 'venue-media');

drop policy if exists "authenticated can upload own venue media" on storage.objects;
create policy "authenticated can upload own venue media" on storage.objects for insert
  to authenticated
  with check (bucket_id = 'venue-media' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "owner can delete own venue media file" on storage.objects;
create policy "owner can delete own venue media file" on storage.objects for delete
  to authenticated
  using (bucket_id = 'venue-media' and (storage.foldername(name))[1] = auth.uid()::text);
