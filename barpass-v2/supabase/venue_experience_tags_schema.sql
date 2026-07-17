-- Venue Intelligence Roadmap Phase 4: Experience Tags.
--
-- Normalized table, not a jsonb/array column on `venues` — chosen for scale:
-- each tag carries its own confidence + source and needs to be independently
-- filterable/indexable ("find venues with tag=X at confidence>=medium"),
-- which a jsonb blob can't do cheaply at millions of rows. This mirrors the
-- existing `events` table's pattern (separate table, venue_id FK) rather
-- than introducing a new denormalization style.
--
-- Populated by scripts/derive-experience-tags.ts — a PURE DERIVATION, zero
-- external API calls. Every tag is computed deterministically from data
-- already in `venues` (the amenity booleans from Phase 1 + venue type +
-- happy_hour), never invented and never AI-guessed. See
-- scripts/experience-tags-rules.ts for the exact rule table.

create table if not exists public.venue_experience_tags (
    id           uuid primary key default gen_random_uuid(),
    venue_id     uuid not null references public.venues(id) on delete cascade,
    tag_id       text not null,
    category     text not null,
    confidence   text not null check (confidence in ('high', 'medium', 'low')),
    source       text not null check (source in ('google_attribute', 'venue_category', 'user_signal', 'future_ai')),
    computed_at  timestamptz not null default now(),
    unique (venue_id, tag_id)
);

create index if not exists venue_experience_tags_venue_id_idx on public.venue_experience_tags (venue_id);
create index if not exists venue_experience_tags_tag_id_idx on public.venue_experience_tags (tag_id);

alter table public.venue_experience_tags enable row level security;

create policy "experience tags are public"
  on public.venue_experience_tags for select
  to anon, authenticated
  using (true);
