-- BarPass Social — venue posts (run in Supabase SQL editor)
-- Posts belong to a venue (Instagram-for-places model).

create table if not exists venue_posts (
  id            uuid primary key default gen_random_uuid(),
  venue_id      uuid not null references venues(id) on delete cascade,
  user_id       uuid references auth.users(id) on delete set null,
  author_handle text not null default 'nightlifer',
  caption       text not null check (char_length(caption) between 1 and 500),
  emoji         text,
  vibe_rating   int check (vibe_rating between 1 and 5),
  drinks_rating int check (drinks_rating between 1 and 5),
  music_rating  int check (music_rating between 1 and 5),
  created_at    timestamptz not null default now()
);

create index if not exists venue_posts_venue_idx on venue_posts (venue_id, created_at desc);

alter table venue_posts enable row level security;

-- Anyone can read the feed.
drop policy if exists "venue_posts_read" on venue_posts;
create policy "venue_posts_read" on venue_posts
  for select using (true);

-- Only authenticated users can post, and only as themselves.
drop policy if exists "venue_posts_insert" on venue_posts;
create policy "venue_posts_insert" on venue_posts
  for insert with check (auth.uid() = user_id);

-- Authors can delete their own posts.
drop policy if exists "venue_posts_delete" on venue_posts;
create policy "venue_posts_delete" on venue_posts
  for delete using (auth.uid() = user_id);
