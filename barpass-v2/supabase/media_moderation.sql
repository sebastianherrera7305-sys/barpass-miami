-- ═══════════════════════════════════════════════════════════════════
-- MEDIA MODERATION — reportar, ocultar, bloquear al que subió
-- ═══════════════════════════════════════════════════════════════════
-- Idempotent, safe to re-run. Run AFTER: venue_media.sql, venue_stories.sql,
-- friend_graph_schema.sql (user_blocks), rate_limits_schema.sql.
--
-- venue_media is public: an anonymous stranger with the anon key gets
-- HTTP 200 and the rows. There is no way to report a photo, no way to
-- block whoever posted it, no way to make it stop being shown. That is
-- Apple 1.2 (user-generated content) and, more to the point, it is a
-- photo of a person, at night, in a bar, with no button on it.
--
--
-- ── THE CONSTRAINT THAT DECIDES EVERY SHAPE BELOW ────────────────
-- venue_stories.sql revokes SELECT on the venue_media TABLE from anon and
-- authenticated and grants back exactly
--   (id, venue_id, media_url, media_type, created_at).
-- NO CLIENT CAN READ user_id. That is not an oversight to work around —
-- it is the reason a public photo does not also publish a named person's
-- location history. Nothing here weakens it. Consequences, and they are
-- the whole design:
--
--   · Reporting cannot name an author, so it is an RPC that takes a
--     MEDIA id and resolves the author server-side, inside the function,
--     where it never reaches the response.
--   · Blocking cannot be a client-side filter, because the client has no
--     author to filter on. It has to happen inside the read path.
--   · "Block whoever posted this" cannot write to public.user_blocks:
--     that table IS client-readable for your own rows
--     (friend_graph_schema.sql grants select + user_blocks_select_own),
--     so blocking an unknown author would hand you their uuid and undo
--     the invariant through the back door. It writes to
--     venue_media_author_mutes instead — same effect on the feed, no row
--     the client can read back. If you actually know who they are, the
--     real block in the friends flow is still there.
--
-- NEW COLUMNS ARE NOT GRANTED. hidden_at / deleted_at / report_count are
-- added to venue_media below and no grant is issued for them, so they
-- stay unreadable by both client roles exactly like user_id. Do not "fix"
-- that by re-granting the table: a column REVOKE under a table GRANT is a
-- silent no-op, which is what cost weeks here already.


-- ═══════════════════════════════════════════════════════════════════
-- 1. STATE ON THE MEDIA ROW
-- ═══════════════════════════════════════════════════════════════════
-- hidden_at is a FLAG, not a deletion: the row stays, the file stays, and
-- one UPDATE undoes it. That is what makes an automatic hide safe enough
-- to fire without a human (see §4).
alter table public.venue_media add column if not exists hidden_at     timestamptz;
alter table public.venue_media add column if not exists hidden_reason text;
alter table public.venue_media add column if not exists deleted_at    timestamptz;
alter table public.venue_media add column if not exists report_count  int not null default 0;

-- Partial: the queue only ever asks for the rows that are flagged, and
-- those are a rounding error against the table.
create index if not exists venue_media_hidden_idx
  on public.venue_media (hidden_at) where hidden_at is not null;


-- ═══════════════════════════════════════════════════════════════════
-- 2. THE REPORTS
-- ═══════════════════════════════════════════════════════════════════
-- unique(media_id, reporter_id) is load-bearing, same as
-- chapter_message_reports: without it one person filing three times
-- trips the threshold alone.
create table if not exists public.venue_media_reports (
  id uuid primary key default gen_random_uuid(),
  media_id uuid not null references public.venue_media(id) on delete cascade,
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  reason text not null,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references public.profiles(id),
  resolved_action text check (resolved_action in ('dismissed', 'hidden', 'removed')),
  unique (media_id, reporter_id)
);

create index if not exists venue_media_reports_media_idx  on public.venue_media_reports (media_id);
create index if not exists venue_media_reports_open_idx   on public.venue_media_reports (resolved_at) where resolved_at is null;
create index if not exists venue_media_reports_person_idx on public.venue_media_reports (reporter_id, created_at desc);

-- "Nobody can read anybody else's reports" is enforced by nobody being
-- able to read ANY of them over the API. The only write path is the RPC
-- in §5 and the only read path is the service role. A per-row SELECT
-- grant was considered and rejected: it buys the client a "you already
-- reported this" flag that the RPC already returns, in exchange for a
-- readable table that also happens to prove which media a given account
-- has been looking at.
alter table public.venue_media_reports enable row level security;
revoke all on public.venue_media_reports from anon, authenticated;

-- A per-viewer mute of an author the viewer can neither see nor name.
-- Deliberately NOT public.user_blocks — see the header.
create table if not exists public.venue_media_author_mutes (
  muter_id  uuid not null references public.profiles(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (muter_id, author_id),
  constraint venue_media_author_mutes_not_self check (muter_id <> author_id)
);

alter table public.venue_media_author_mutes enable row level security;
revoke all on public.venue_media_author_mutes from anon, authenticated;

-- Snapshot at the moment a media stops existing — the author's own
-- delete included, which until now dropped the row and orphaned the file
-- with nothing recording that it had ever been there.
create table if not exists public.venue_media_archive (
  id uuid primary key default gen_random_uuid(),
  original_media_id uuid not null,
  venue_id uuid,
  user_id uuid,
  media_url text,
  media_type text,
  created_at timestamptz,
  report_count int,
  hidden_at timestamptz,
  hidden_reason text,
  archived_at timestamptz not null default now(),
  archive_reason text
);

alter table public.venue_media_archive enable row level security;
revoke all on public.venue_media_archive from anon, authenticated;

-- The file is in S3; the row in storage.objects is what the public URL
-- resolves through. Deleting that row 404s the link immediately, but the
-- BYTES only go away through the Storage API, which SQL cannot call. So
-- every removal enqueues the path here and a service-role drain finishes
-- the job (§7). Queue, not fire-and-forget, because a purge that fails
-- silently is a photo that is still on the internet.
create table if not exists public.venue_media_purge_queue (
  storage_path text primary key,
  media_id uuid,
  enqueued_at timestamptz not null default now(),
  object_row_deleted boolean not null default false,
  purged_at timestamptz,
  last_error text
);

alter table public.venue_media_purge_queue enable row level security;
revoke all on public.venue_media_purge_queue from anon, authenticated;


-- ═══════════════════════════════════════════════════════════════════
-- 3. THE REASONS, AND WHY EACH ONE IS ON THE LIST
-- ═══════════════════════════════════════════════════════════════════
-- Apple asks for CATEGORIES, not a free-text box, and the categories are
-- what lets a threshold mean anything: "3 people said something" is
-- noise, "3 people said harassment" is a signal. There is no free-text
-- field at all, on purpose — a note written by a reporter is itself
-- user-generated content that would need moderating, can be aimed at the
-- author or at whoever reads the queue, and adds nothing the reviewer
-- cannot see by looking at the photo.
--
--   depicts_me   salgo yo y no di permiso. THE reason this file exists.
--                A photo of a person in a bar at night, posted by someone
--                else. Consent is not a majority vote → tier 1.
--   sexual       nudity / sexual content.                        tier 1
--   minor        a minor, or a minor drinking or sexualised. In a 21+
--                app this is both child safety and liability.    tier 1
--   violence     a fight, an injury, a weapon.                   tier 2
--   hate         slurs, hate symbols, targeting a group.         tier 2
--   harassment   posted to humiliate or target one person.       tier 2
--   illegal      drugs, underage drinking, a crime on camera.    tier 2
--   spam         promo, an ad, a link — not a moment of a night. tier 3
--   wrong_venue  not this bar. Not offensive, but it corrupts the one
--                thing a story claims: WHERE everybody is.       tier 3
--   other        the escape hatch that keeps the other nine honest, at
--                the weakest weight.                             tier 3
--
-- Missing on purpose: self-harm and "I'm in danger". Those are not a
-- moderation queue's job and routing them here would be a promise this
-- file cannot keep.
alter table public.venue_media_reports drop constraint if exists venue_media_reports_reason_check;
alter table public.venue_media_reports add constraint venue_media_reports_reason_check
  check (reason in ('depicts_me','sexual','minor','violence','hate',
                    'harassment','illegal','spam','wrong_venue','other'));

create or replace function public.bp_media_reason_tier(p_reason text)
returns int language sql immutable set search_path = public, extensions as $$
  select case p_reason
    when 'depicts_me' then 1 when 'sexual' then 1 when 'minor' then 1
    when 'violence' then 2 when 'hate' then 2
    when 'harassment' then 2 when 'illegal' then 2
    when 'spam' then 3 when 'wrong_venue' then 3 when 'other' then 3
  end;
$$;


-- ═══════════════════════════════════════════════════════════════════
-- 4. AUTOMATIC HIDING — the number, and the abuse of the number
-- ═══════════════════════════════════════════════════════════════════
-- Apple asks for "timely responses". Nobody is watching a queue at 3am,
-- and a story's entire life is one night: a review that happens tomorrow
-- has already failed. So the photo has to be able to stop showing before
-- a human looks at it.
--
-- THE THRESHOLDS
--   tier 1        → 1 weighted report.  These are the three where the
--                   second and third report arrive too late to matter.
--   tier 1-2      → 2 weighted reports.
--   any tier      → 3 weighted reports. Same number chapter_chat.sql
--                   uses, and it is if anything conservative here: a
--                   chapter message is seen by people who know each
--                   other, a venue story by strangers, so three
--                   independent strangers converging is a stronger
--                   signal, not a weaker one.
--
-- WHY SO LOW: the two errors do not cost the same. A wrongly hidden bar
-- photo costs its author a story that was going to expire at 6am anyway,
-- and is undone by one UPDATE. A wrongly kept photo of a person can cost
-- that person a great deal, and every hour it stays up is more of it.
-- Asymmetric costs, asymmetric threshold.
--
-- THE ABUSE, WRITTEN DOWN INSTEAD OF WISHED AWAY
-- Three coordinated accounts — one, for tier 1 — can take down anybody's
-- photo. That is true and it is not fully fixable in SQL. What is done
-- about it:
--   1. An automatic hide DESTROYS NOTHING. Flag only: row, file and the
--      author's own copy untouched.
--   2. It is never a punishment. No strike, no ban, no effect on the
--      account. Only a human `remove` does anything durable.
--   3. Dismissal has teeth. A human dismissal un-hides AND marks every
--      report on that media dismissed; a reporter with 3+ dismissed
--      reports and a >=2/3 dismissal rate drops to weight 0 — still able
--      to file, no longer able to hide anything. A brigade works once.
--   4. An account younger than 24h carries weight 0 on tiers 2 and 3.
--      Free instant signup is the cheap brigade; this taxes it without
--      touching a real user, who has had the app since before tonight.
--      Tier 1 is deliberately exempt: "salgo yo en esa foto" is exactly
--      the case where someone installs the app tonight because they just
--      found out, and refusing them is the wrong error to make.
--   5. Tier-1 hides sort to the TOP of the review queue precisely
--      because they are the cheapest to abuse and the worst to ignore.
-- What remains unfixed: a determined group of real, aged accounts. That
-- needs a person. Automatic hiding buys TIME; it does not replace review.

create or replace function public.bp_report_weight(p_reporter uuid, p_tier int)
returns int language plpgsql stable security definer
set search_path = public, extensions as $$
declare
  v_dismissed int;
  v_judged int;
  v_age interval;
begin
  select count(*) filter (where resolved_action = 'dismissed'),
         count(*) filter (where resolved_at is not null)
    into v_dismissed, v_judged
    from public.venue_media_reports where reporter_id = p_reporter;

  -- Judged wrong by a human, repeatedly. Never an automatic verdict.
  if v_dismissed >= 3 and v_dismissed::numeric / greatest(v_judged, 1) >= 0.67 then
    return 0;
  end if;

  select now() - created_at into v_age from public.profiles where id = p_reporter;
  if p_tier > 1 and coalesce(v_age, interval '100 years') < interval '24 hours' then
    return 0;
  end if;

  return 1;
end; $$;

create or replace function public.bp_evaluate_media_hide(p_media_id uuid)
returns boolean language plpgsql security definer
set search_path = public, extensions as $$
declare
  v_t1 int; v_t12 int; v_all int;
begin
  select coalesce(sum(w) filter (where tier = 1), 0),
         coalesce(sum(w) filter (where tier <= 2), 0),
         coalesce(sum(w), 0)
    into v_t1, v_t12, v_all
    from (
      select public.bp_media_reason_tier(r.reason) as tier,
             public.bp_report_weight(r.reporter_id,
                                     public.bp_media_reason_tier(r.reason)) as w
        from public.venue_media_reports r
       where r.media_id = p_media_id
         and r.resolved_action is distinct from 'dismissed'
    ) s;

  -- report_count is the RAW number of reporters, not the weighted one:
  -- weights decide the hide, the count describes the situation to whoever
  -- opens the queue. Collapsing them would hide a brigade of zero-weight
  -- accounts from the only person who can recognise it.
  update public.venue_media m
     set report_count = (select count(*) from public.venue_media_reports r
                          where r.media_id = p_media_id)
   where m.id = p_media_id;

  if v_t1 >= 1 or v_t12 >= 2 or v_all >= 3 then
    update public.venue_media
       set hidden_at = now(),
           hidden_reason = case when v_t1 >= 1 then 'auto_tier1' else 'auto_reports' end
     where id = p_media_id and hidden_at is null and deleted_at is null;
    return true;
  end if;
  return false;
end; $$;


-- ═══════════════════════════════════════════════════════════════════
-- 5. THE CLIENT RPCs — a media id goes in, no author ever comes out
-- ═══════════════════════════════════════════════════════════════════
create or replace function public.report_venue_media(p_media_id uuid, p_reason text)
returns table (report_id uuid, already_reported boolean)
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_uid uuid := auth.uid();
  v_author uuid;
  v_existing uuid;
  v_id uuid;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  if public.bp_media_reason_tier(p_reason) is null then raise exception 'invalid_reason'; end if;

  -- The author is resolved HERE, used for one comparison, and never
  -- written to the result. This local variable is the entire reason this
  -- is an RPC and not an INSERT the client could do itself.
  select m.user_id into v_author from public.venue_media m where m.id = p_media_id;
  if v_author is null then raise exception 'media_not_found'; end if;
  if v_author = v_uid then raise exception 'own_media'; end if;

  -- Duplicate check BEFORE the rate limit: re-tapping report on something
  -- you already reported must not spend budget you may need tonight.
  select r.id into v_existing from public.venue_media_reports r
   where r.media_id = p_media_id and r.reporter_id = v_uid;
  if v_existing is not null then
    return query select v_existing, true;
    return;
  end if;

  -- Per reporter, not per media. A person cleaning up one bad night files
  -- a handful; 6/h and 20/day sit far above real use and far below "walk
  -- one account through a venue's whole feed".
  if not public.check_rate_limit('media_report_h:' || v_uid::text, 6, 3600)
     or not public.check_rate_limit('media_report_d:' || v_uid::text, 20, 86400) then
    raise exception 'rate_limit_exceeded';
  end if;

  insert into public.venue_media_reports (media_id, reporter_id, reason)
  values (p_media_id, v_uid, p_reason)
  returning id into v_id;

  perform public.bp_evaluate_media_hide(p_media_id);

  -- Deliberately NOT returning whether this tipped it into hiding. On a
  -- tier-1 reason that single bit would teach any caller that one report
  -- is enough, which is the instruction manual for abusing it. The
  -- reporter stops seeing the media either way (§6), so the UI has
  -- nothing to say that this does not already support.
  return query select v_id, false;
end; $$;

-- "No quiero ver más nada de quien subió esto" without ever learning who
-- that is. Writes the mute table, never user_blocks.
create or replace function public.mute_venue_media_author(p_media_id uuid)
returns void language plpgsql security definer
set search_path = public, extensions as $$
declare
  v_uid uuid := auth.uid();
  v_author uuid;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  select m.user_id into v_author from public.venue_media m where m.id = p_media_id;
  if v_author is null then raise exception 'media_not_found'; end if;
  if v_author = v_uid then raise exception 'own_media'; end if;
  insert into public.venue_media_author_mutes (muter_id, author_id)
  values (v_uid, v_author) on conflict do nothing;
end; $$;

-- Undo, addressed the only way the client can address anything: by a
-- media id it can still see. Once that media is gone there is no handle
-- left, which is why the reset below exists.
create or replace function public.unmute_venue_media_author(p_media_id uuid)
returns void language plpgsql security definer
set search_path = public, extensions as $$
declare
  v_uid uuid := auth.uid();
  v_author uuid;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  select m.user_id into v_author from public.venue_media m where m.id = p_media_id;
  if v_author is null then raise exception 'media_not_found'; end if;
  delete from public.venue_media_author_mutes
   where muter_id = v_uid and author_id = v_author;
end; $$;

create or replace function public.clear_venue_media_author_mutes()
returns void language sql security definer
set search_path = public, extensions as $$
  delete from public.venue_media_author_mutes where muter_id = auth.uid();
$$;


-- ═══════════════════════════════════════════════════════════════════
-- 6. THE READ PATH — two enforcement points, because there are two reads
-- ═══════════════════════════════════════════════════════════════════
-- DECISION: keep the VIEWS, do not turn the reads into RPCs.
--
-- The security argument that would favour an RPC does not apply: the
-- views are already security_invoker = false, so they run as the owner
-- and can read user_id while their callers cannot. An RPC would buy that
-- same property a second time.
--
-- The cost argument decides it, and it is not view-vs-RPC — it is
-- per-request-vs-per-row. VenueStoryPulseStore issues ONE request for the
-- whole catalogue and every card in the feed reads a dictionary from it
-- ("Stop downloading 23 cities to show one" is what happens otherwise).
-- Inside that one request the exclusion set is built ONCE, as a
-- materialized CTE, and anti-joined against a live-story set that is a
-- handful of rows because the view is already bounded to the night in
-- progress. The expensive shape would have been asking "is this author
-- blocked" once per row — bp_blocked_between() in a loop — and that is
-- what the CTE avoids. An RPC would do identical work behind an extra
-- function boundary, lose the filter/order pushdown PostgREST gets on a
-- view, and force the anon (logged-out) story read to be re-granted.
--
-- Cost of keeping views: the pulse is now VIEWER-DEPENDENT, so it cannot
-- be cached across users. It never was — it is a live query over the
-- night in progress — so nothing is lost. Second cost: poster_seq is a
-- dense_rank over the FILTERED set, so two viewers can number the same
-- frame differently. That is fine, it is only ever used to group frames
-- within one response, and it is the correct behaviour: a blocked
-- person must not be counted in the crowd you are shown.

drop view if exists public.venue_story_pulse;
drop view if exists public.venue_stories;

create view public.venue_stories as
with viewer as (select auth.uid() as uid),
-- Built once per request. Both directions: someone I blocked, and
-- someone who blocked me — the second is the one a client-side filter
-- could never do, because the client is not told it happened.
invisible_authors as materialized (
    select b.blocked_id as other_id from public.user_blocks b, viewer v
     where v.uid is not null and b.blocker_id = v.uid
    union
    select b.blocker_id from public.user_blocks b, viewer v
     where v.uid is not null and b.blocked_id = v.uid
    union
    select m.author_id from public.venue_media_author_mutes m, viewer v
     where v.uid is not null and m.muter_id = v.uid
),
-- Reporting something is also a statement about what you want to see.
-- This is what lets the report RPC stay silent about thresholds: the
-- thing disappears for the person who reported it, immediately, whatever
-- the server decides about everyone else.
my_reports as materialized (
    select r.media_id from public.venue_media_reports r, viewer v
     where v.uid is not null and r.reporter_id = v.uid
),
recent as (
    select m.id, m.venue_id, m.user_id, m.media_url, m.media_type, m.created_at,
           public.bp_night_of(m.created_at, v.timezone) as night_date,
           v.timezone                                   as venue_timezone
      from public.venue_media m
      join public.venues v on v.id = m.venue_id
     where m.created_at > now() - interval '30 hours'
       and m.hidden_at is null
       and m.deleted_at is null
       and not exists (select 1 from invisible_authors i where i.other_id = m.user_id)
       and not exists (select 1 from my_reports r where r.media_id = m.id)
),
live as (
    select r.*, public.bp_night_end(r.night_date, r.venue_timezone) as expires_at
      from recent r
     where public.bp_night_end(r.night_date, r.venue_timezone) > now()
),
grouped as (
    select l.*, min(l.created_at) over (partition by l.venue_id, l.user_id) as poster_first_at
      from live l
)
select g.id,
       g.venue_id,
       g.media_url,
       g.media_type,
       g.created_at,
       g.night_date,
       g.expires_at,
       dense_rank() over (
           partition by g.venue_id order by g.poster_first_at, g.user_id
       )::int as poster_seq,
       coalesce(g.user_id = auth.uid(), false) as is_mine
  from grouped g;

alter view public.venue_stories set (security_invoker = false);

create view public.venue_story_pulse as
select s.venue_id,
       count(*)::int                                          as story_count,
       max(s.poster_seq)::int                                 as poster_count,
       max(s.created_at)                                      as latest_at,
       min(s.night_date)                                      as night_date,
       (array_agg(s.media_url  order by s.created_at desc))[1] as latest_media_url,
       (array_agg(s.media_type order by s.created_at desc))[1] as latest_media_type
  from public.venue_stories s
 group by s.venue_id;

alter view public.venue_story_pulse set (security_invoker = false);

grant select on public.venue_stories     to anon, authenticated;
grant select on public.venue_story_pulse to anon, authenticated;

-- ── THE SECOND READ PATH ──────────────────────────────────────────
-- The venue photo grid reads public.venue_media DIRECTLY over PostgREST
-- (VenueMediaRepository.media(for:)), and the views above cannot help it
-- because they bypass RLS as the owner and it does not go through them.
-- So the base table needs its own policy. Two enforcement points because
-- there are two reads; verification (h) checks both, and a new read path
-- added later must pick one of them or it gets nothing.
--
-- It has to be a SECURITY DEFINER function and it has to take a MEDIA id:
--   · a policy cannot read public.user_blocks inline — anon has no grant
--     on it at all, and `authenticated` only sees rows where it is the
--     blocker, which is exactly the half that does not need checking;
--   · bp_blocked_between() is revoked from every client role on purpose
--     (feed it uuid pairs and it answers: a relationship oracle), and
--     anything taking an author uuid would be the same oracle again.
-- Given a media id, all this can tell a caller is "this particular photo
-- is not for you", which the feed already tells them by leaving it out.
--
-- It reads venue_media from inside venue_media's own policy. That does
-- not recurse because the owner bypasses RLS. DO NOT run
-- `alter table public.venue_media force row level security` — that would
-- make this infinitely recursive, and it is the only thing that would.
create or replace function public.bp_media_hidden_from_me(p_media_id uuid)
returns boolean language sql stable security definer
set search_path = public, extensions as $$
  select exists (
    select 1 from public.venue_media m
     where m.id = p_media_id
       and (m.hidden_at is not null
         or m.deleted_at is not null
         or exists (select 1 from public.user_blocks b
                     where (b.blocker_id = auth.uid() and b.blocked_id = m.user_id)
                        or (b.blocked_id = auth.uid() and b.blocker_id = m.user_id))
         or exists (select 1 from public.venue_media_author_mutes mu
                     where mu.muter_id = auth.uid() and mu.author_id = m.user_id)
         or exists (select 1 from public.venue_media_reports r
                     where r.media_id = m.id and r.reporter_id = auth.uid()))
  );
$$;

-- The two null tests are first on purpose: they are free, they catch the
-- moderated rows, and the planner orders the 100-cost function call last,
-- so the ordinary case never pays for it.
-- This hides an author's own moderated media FROM THE AUTHOR too. That is
-- deliberate: a row that stays visible only to its owner looks completely
-- normal to them, so they learn nothing, while the honest alternative —
-- telling them it was reported — is a notification feature that does not
-- exist yet. Vanishing is the smaller lie, and it also means a brigade
-- has to be re-spent if the author simply posts again.
drop policy if exists "venue media is public" on public.venue_media;
create policy "venue media is public" on public.venue_media for select
  to anon, authenticated
  using (hidden_at is null and deleted_at is null
         and not public.bp_media_hidden_from_me(id));


-- ═══════════════════════════════════════════════════════════════════
-- 7. THE REVIEWER, AND KILLING THE FILE
-- ═══════════════════════════════════════════════════════════════════
create or replace function public.bp_storage_path_of(p_media_url text)
returns text language sql immutable set search_path = public, extensions as $$
  select nullif(split_part(p_media_url, '/storage/v1/object/public/venue-media/', 2), '');
$$;

-- Deleting the storage.objects row is what stops the public URL: the
-- Storage API resolves every download through that row, so it starts
-- answering 404 at once. It does NOT free the bytes in S3, and a CDN edge
-- may keep serving a cached copy until its TTL expires. Both of those are
-- why the queue exists and why this function is not allowed to fail
-- quietly: whether the row went is recorded either way.
create or replace function public.bp_purge_venue_media_file(p_media_id uuid, p_media_url text)
returns void language plpgsql security definer
set search_path = public, extensions as $$
declare
  v_path text := public.bp_storage_path_of(p_media_url);
begin
  if v_path is null then return; end if;

  insert into public.venue_media_purge_queue (storage_path, media_id)
  values (v_path, p_media_id) on conflict (storage_path) do nothing;

  -- Whether `postgres` may delete from storage.objects is a property of
  -- the project, not of this file — so it is attempted, and a failure
  -- leaves a queue row with the reason rather than an exception that
  -- rolls back the removal the reviewer actually asked for.
  begin
    delete from storage.objects where bucket_id = 'venue-media' and name = v_path;
    update public.venue_media_purge_queue
       set object_row_deleted = true, last_error = null where storage_path = v_path;
  exception when others then
    update public.venue_media_purge_queue
       set object_row_deleted = false, last_error = sqlerrm where storage_path = v_path;
  end;
end; $$;

-- The author deleting their own photo used to drop the row and leave the
-- file on a public URL forever. Now it archives and enqueues too.
create or replace function public.bp_venue_media_before_delete()
returns trigger language plpgsql security definer
set search_path = public, extensions as $$
begin
  insert into public.venue_media_archive
    (original_media_id, venue_id, user_id, media_url, media_type,
     created_at, report_count, hidden_at, hidden_reason, archive_reason)
  values
    (old.id, old.venue_id, old.user_id, old.media_url, old.media_type,
     old.created_at, old.report_count, old.hidden_at, old.hidden_reason, 'row_deleted');
  perform public.bp_purge_venue_media_file(old.id, old.media_url);
  return old;
end; $$;

drop trigger if exists trg_venue_media_before_delete on public.venue_media;
create trigger trg_venue_media_before_delete
  before delete on public.venue_media
  for each row execute function public.bp_venue_media_before_delete();

-- Tier first, then the ones already auto-hidden, then oldest: a tier-1
-- hide is both the most urgent if real and the cheapest to fake, so it is
-- the first thing a human should be looking at.
-- Dropped rather than replaced: `create or replace view` refuses any
-- change to the column list, so a re-run after editing this shape would
-- fail instead of updating.
drop view if exists public.venue_media_review_queue;
create view public.venue_media_review_queue as
select m.id                                            as media_id,
       m.venue_id,
       v.name                                          as venue_name,
       m.media_url,
       m.media_type,
       m.created_at,
       m.hidden_at,
       m.hidden_reason,
       m.report_count,
       min(public.bp_media_reason_tier(r.reason))      as worst_tier,
       array_agg(distinct r.reason)                    as reasons,
       count(*) filter (where r.resolved_at is null)::int as open_reports
  from public.venue_media m
  join public.venues v on v.id = m.venue_id
  join public.venue_media_reports r on r.media_id = m.id
 where m.deleted_at is null and r.resolved_at is null
 group by m.id, m.venue_id, v.name, m.media_url, m.media_type,
          m.created_at, m.hidden_at, m.hidden_reason, m.report_count
 order by min(public.bp_media_reason_tier(r.reason)),
          m.hidden_at nulls last, m.created_at;

-- Supabase's default privileges grant new tables and views to anon and
-- authenticated. Without this revoke the queue would be world-readable
-- the moment it was created — and the queue is a list of exactly the
-- photos somebody complained about.
revoke all on public.venue_media_review_queue from anon, authenticated;

-- `remove` is a TOMBSTONE, not a DELETE. A hard delete would cascade the
-- reports away with it and leave nothing to show that a decision was ever
-- made, or who kept filing reports that stuck.
create or replace function public.moderate_venue_media(
  p_media_id uuid, p_action text, p_note text default null)
returns void language plpgsql security definer
set search_path = public, extensions as $$
declare
  v_url text;
begin
  if p_action not in ('remove', 'dismiss', 'hide') then
    raise exception 'invalid_action';
  end if;

  select media_url into v_url from public.venue_media where id = p_media_id;
  if v_url is null then raise exception 'media_not_found'; end if;

  if p_action = 'remove' then
    insert into public.venue_media_archive
      (original_media_id, venue_id, user_id, media_url, media_type,
       created_at, report_count, hidden_at, hidden_reason, archive_reason)
    select id, venue_id, user_id, media_url, media_type, created_at,
           report_count, hidden_at, hidden_reason,
           coalesce('moderator_removed: ' || p_note, 'moderator_removed')
      from public.venue_media where id = p_media_id;

    perform public.bp_purge_venue_media_file(p_media_id, v_url);

    update public.venue_media
       set deleted_at = now(), hidden_at = coalesce(hidden_at, now()),
           hidden_reason = 'moderator_removed'
     where id = p_media_id;

  elsif p_action = 'hide' then
    update public.venue_media
       set hidden_at = coalesce(hidden_at, now()), hidden_reason = 'moderator_hidden'
     where id = p_media_id;

  else -- dismiss: the photo comes back, and the reporters carry the cost
    update public.venue_media
       set hidden_at = null, hidden_reason = null
     where id = p_media_id;
  end if;

  update public.venue_media_reports
     set resolved_at = now(),
         resolved_by = auth.uid(),
         resolved_action = case p_action when 'remove' then 'removed'
                                         when 'hide'   then 'hidden'
                                         else 'dismissed' end
   where media_id = p_media_id and resolved_at is null;
end; $$;


-- ═══════════════════════════════════════════════════════════════════
-- 8. GRANTS
-- ═══════════════════════════════════════════════════════════════════
do $$
declare v_sig text;
begin
  foreach v_sig in array array[
    'public.bp_media_reason_tier(text)',
    'public.bp_report_weight(uuid, int)',
    'public.bp_evaluate_media_hide(uuid)',
    'public.bp_storage_path_of(text)',
    'public.bp_purge_venue_media_file(uuid, text)',
    'public.bp_venue_media_before_delete()',
    'public.bp_media_hidden_from_me(uuid)',
    'public.report_venue_media(uuid, text)',
    'public.mute_venue_media_author(uuid)',
    'public.unmute_venue_media_author(uuid)',
    'public.clear_venue_media_author_mutes()',
    'public.moderate_venue_media(uuid, text, text)'
  ] loop
    execute format('revoke execute on function %s from public, anon, authenticated', v_sig);
  end loop;
end $$;

-- The RLS policy in §6 is evaluated as the INVOKING role, so both client
-- roles need EXECUTE on this one or every read of venue_media fails.
grant execute on function public.bp_media_hidden_from_me(uuid)        to anon, authenticated;

grant execute on function public.report_venue_media(uuid, text)       to authenticated;
grant execute on function public.mute_venue_media_author(uuid)        to authenticated;
grant execute on function public.unmute_venue_media_author(uuid)      to authenticated;
grant execute on function public.clear_venue_media_author_mutes()     to authenticated;

-- Reviewing is service-role only. There is no moderator role in this
-- project (chapter_messages_archive set the same precedent), and adding
-- one here would mean deciding who gets to see a list of reported photos
-- of people — a decision that belongs to whoever runs the company, not to
-- a migration.
grant execute on function public.moderate_venue_media(uuid, text, text) to service_role;

notify pgrst, 'reload schema';


-- ═══════════════════════════════════════════════════════════════════
-- 9. VERIFICATION  (run by hand; every one of these must hold)
-- ═══════════════════════════════════════════════════════════════════
--
-- (a) The invariant did not move. Expect 0 rows:
--   select grantee, privilege_type, column_name
--     from information_schema.column_privileges
--    where table_schema='public' and table_name='venue_media'
--      and column_name in ('user_id','hidden_at','deleted_at','report_count')
--      and grantee in ('anon','authenticated');
--
-- (b) No client role can read any moderation table. Expect 0 rows:
--   select table_name, grantee, privilege_type
--     from information_schema.role_table_grants
--    where table_schema='public'
--      and table_name in ('venue_media_reports','venue_media_author_mutes',
--                         'venue_media_archive','venue_media_purge_queue',
--                         'venue_media_review_queue')
--      and grantee in ('anon','authenticated');
--
-- (c) anon can execute exactly one function here — the one the policy
--     needs. Expect exactly bp_media_hidden_from_me:
--   select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
--    where n.nspname='public'
--      and (p.proname like '%venue_media%' or p.proname like 'bp_media%'
--           or p.proname like 'bp_report_weight')
--      and has_function_privilege('anon', p.oid, 'EXECUTE');
--
-- (d) Every function pins a search_path that includes extensions.
--     Expect every row to show {search_path=public, extensions}:
--   select p.proname, p.proconfig from pg_proc p
--     join pg_namespace n on n.oid=p.pronamespace
--    where n.nspname='public'
--      and (p.proname like '%venue_media%' or p.proname like 'bp_media%'
--           or p.proname = 'bp_report_weight');
--
-- (e) The reply to a report says nothing about the author. Signed in as
--     someone who is NOT the poster, on a real media id:
--       select * from public.report_venue_media('<media>'::uuid, 'spam');
--     Expect two columns, report_id and already_reported=false. Run it a
--     second time: same report_id, already_reported=true, and
--       select count(*) from public.venue_media_reports where media_id='<media>';
--     must still be 1.
--
-- (f) A tier-1 report hides on its own, from one account:
--       select * from public.report_venue_media('<media>'::uuid, 'depicts_me');
--       select hidden_at, hidden_reason, report_count
--         from public.venue_media where id='<media>';   -- hidden_reason=auto_tier1
--     And a tier-3 one does not: on a fresh media, one 'spam' report must
--     leave hidden_at null.
--
-- (g) Fresh accounts cannot auto-hide on the consensus tiers. With a
--     profile created less than 24h ago:
--       select public.bp_report_weight('<new uid>'::uuid, 3);  -- 0
--       select public.bp_report_weight('<new uid>'::uuid, 1);  -- 1
--
-- (h) BOTH READ PATHS DROP IT. With the media hidden, as anon:
--   curl -s "https://<PROJECT_REF>.supabase.co/rest/v1/venue_media?select=id&id=eq.<media>" \
--        -H "apikey: $SUPABASE_ANON_KEY" -H "Authorization: Bearer $SUPABASE_ANON_KEY"
--        # expect: []
--   curl -s "https://<PROJECT_REF>.supabase.co/rest/v1/venue_stories?select=id&id=eq.<media>" \
--        -H "apikey: $SUPABASE_ANON_KEY" -H "Authorization: Bearer $SUPABASE_ANON_KEY"
--        # expect: []
--     If the first one returns the row, the policy did not take — that is
--     the venue photo grid still serving a reported photo.
--
-- (i) Blocking works in BOTH directions, which is the half a client
--     filter could never do. A posts a story; as B:
--       select public.block_user('<A>'::uuid);
--       select count(*) from public.venue_stories where id='<A media>'; -- 0
--     Now undo, and have A block B instead. As B, the same count must
--     still be 0 — B was never told the block happened.
--
-- (j) Reporting makes it vanish for the reporter immediately, whatever
--     the threshold decided. On a media with ONE tier-3 report from B:
--       -- as B:       select count(*) from public.venue_stories where id='<media>'; -- 0
--       -- as anyone else: same query                                                -- 1
--
-- (k) The mute does not leak the author into anything the client reads.
--       select public.mute_venue_media_author('<media>'::uuid);
--       select count(*) from public.user_blocks where blocker_id = auth.uid();
--     must be unchanged, and
--   curl -s ".../rest/v1/venue_media_author_mutes?select=*" ... # expect 42501/404
--
-- (l) The pulse count follows the filtering. With A's frames excluded for
--     B, `poster_count` from venue_story_pulse must be one lower for B
--     than for a third account that blocked nobody.
--
-- (m) Removal actually kills the file. As service_role:
--       select public.moderate_venue_media('<media>'::uuid, 'remove', 'test');
--       select * from public.venue_media_purge_queue where media_id='<media>';
--     object_row_deleted must be true. Then fetch the media_url in a
--     browser: expect 404 (a CDN edge may serve a cached copy until its
--     TTL — that is what the drain in the next note is for). If
--     object_row_deleted is false, read last_error: this project does not
--     let `postgres` write storage.objects and the drain is now the ONLY
--     thing removing the file.
--
-- (n) Dismissal restores, and costs the reporters:
--       select public.moderate_venue_media('<media>'::uuid, 'dismiss', null);
--       select hidden_at from public.venue_media where id='<media>';  -- null
--       select resolved_action from public.venue_media_reports where media_id='<media>';
--                                                                     -- dismissed
--     After three such dismissals against one reporter:
--       select public.bp_report_weight('<reporter>'::uuid, 2);        -- 0
--
-- (o) The author's own delete no longer orphans a file:
--       delete from public.venue_media where id='<own media>';
--       select * from public.venue_media_archive where original_media_id='<own media>';
--       select * from public.venue_media_purge_queue where media_id='<own media>';
--
--
-- ── DRAINING THE PURGE QUEUE (service role, outside Postgres) ──────
-- SQL cannot call the Storage API, so the bytes go on the way out:
--   select storage_path from public.venue_media_purge_queue where purged_at is null;
-- then, for each, with the SERVICE ROLE key (never the anon key):
--   curl -X DELETE "https://<PROJECT_REF>.supabase.co/storage/v1/object/venue-media/<path>" \
--        -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY"
-- and mark it:
--   update public.venue_media_purge_queue set purged_at = now() where storage_path = '<path>';
-- Until something runs that on a schedule, a removed photo is 404 on its
-- public URL but its bytes are still in the bucket. Say that out loud
-- rather than assuming the row delete was the whole job.
