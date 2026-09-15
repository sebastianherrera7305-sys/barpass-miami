-- ─────────────────────────────────────────────────────────────────────────
-- BarPass — GRANT ONE PERSON ACCESS TO ONE VENUE'S DASHBOARD.
--
-- Run this in the Supabase SQL editor (which runs as the service role, the
-- only role allowed to write `venue_owners`). Idempotent: running it twice
-- changes nothing the second time.
--
-- WHY THERE IS NO "CLAIM YOUR VENUE" BUTTON
-- -----------------------------------------
-- A venue_owners row is what lets an account edit a real bar's listing
-- content, read that bar's revenue, and post a night AS the venue rather than
-- as a promoter (the host_type trigger in host_event_types.sql checks this
-- exact table). Anyone who can grant it to themselves can impersonate a club.
-- So ops grants it by hand, after talking to the venue. `venue_owners` has a
-- SELECT policy only — no INSERT/UPDATE/DELETE policy exists for anon or
-- authenticated, on purpose.
--
-- BEFORE YOU RUN THIS, the person must have signed up once in BarPass (web or
-- iOS) so that `auth.users` has a row for their email. This script will refuse
-- rather than invent one.
--
-- ═════════════════════════════════════════════════════════════════════════
-- STEP 1 — FILL IN THE TWO VALUES IN THE `params` BLOCK BELOW.
--
--   owner_email : the email they signed up with. Find/confirm it with
--                 select id, email, created_at from auth.users
--                  where email ilike '%name%';
--
--   venue_slug  : the venue's slug — the last part of its BarPass web address,
--                 e.g. barpass-v2.vercel.app/venues/blackbird-ordinary
--                 → 'blackbird-ordinary'. Find it with
--                 select slug, name, city, neighborhood, excluded_reason,
--                        business_status
--                   from public.venues
--                  where name ilike '%macdinton%';
--                 Names repeat across (and within) cities — 4,400+ rows,
--                 several "Miller's Ale House" among them — so match on the
--                 SLUG (unique) and eyeball the city before you commit.
--
-- STEP 2 — run the whole file. STEP 3 — run the VERIFICATION queries at the
-- bottom and read what they say.
-- ═════════════════════════════════════════════════════════════════════════

do $$
declare
  -- ← STEP 1a: the email they signed up with.
  v_owner_email text := 'owner@example.com';
  -- ← STEP 1b: the venue's slug (unique; names are not).
  v_venue_slug  text := 'example-venue-slug';
  -- 'owner' or 'manager' — the app treats both as "speaks for this venue"
  -- today; the distinction is recorded for when it stops being true.
  v_role        text := 'owner';

  v_user_id    uuid;
  v_venue_id   uuid;
  v_venue_name text;
  v_venue_city text;
  v_excluded   text;
  v_status     text;
begin
  select u.id into v_user_id
    from auth.users u
   where lower(u.email) = lower(v_owner_email);

  if v_user_id is null then
    raise exception
      'No auth.users row for %. They must sign up in BarPass first — do not create the account for them.',
      v_owner_email;
  end if;

  select v.id, v.name, v.city, v.excluded_reason, v.business_status
    into v_venue_id, v_venue_name, v_venue_city, v_excluded, v_status
    from public.venues v
   where v.slug = v_venue_slug;

  if v_venue_id is null then
    raise exception
      'No venue with slug %. Check it against public.venues before granting anything.',
      v_venue_slug;
  end if;

  insert into public.venue_owners (user_id, venue_id, role)
  values (v_user_id, v_venue_id, v_role)
  on conflict (user_id, venue_id) do update set role = excluded.role;

  raise notice 'Granted % to % on % (%, %)',
    v_role, v_owner_email, v_venue_name, coalesce(v_venue_city, 'no city'), v_venue_id;

  -- Not a failure — a venue can be hidden and still have an owner, who now
  -- gets told why they are hidden. But ops should know before the call.
  if v_excluded is not null then
    raise notice 'HEADS UP: this venue is excluded from the apps. Reason on file: %', v_excluded;
  end if;
  if v_status = 'CLOSED_PERMANENTLY' then
    raise notice 'HEADS UP: Google reports this venue as permanently closed, so it is not served.';
  end if;
end $$;

-- The block above either raises (and changes nothing) or prints a NOTICE
-- naming the venue it granted. Read that notice: it is how you catch having
-- pasted the slug of a same-named bar in another city.

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICATION — run these after, and read them.
-- ═══════════════════════════════════════════════════════════════════

-- 1. The grant exists, and it points at the venue you meant.
--    Expect exactly one row, with the right venue name AND city.
--    select vo.role, vo.created_at, u.email,
--           v.name, v.city, v.neighborhood, v.slug
--      from public.venue_owners vo
--      join auth.users u on u.id = vo.user_id
--      join public.venues v on v.id = vo.venue_id
--     where lower(u.email) = lower('owner@example.com');

-- 2. Will this venue actually appear in the apps? Both columns must be
--    checked, and they answer different questions: excluded_reason is
--    "does it belong in a nightlife app", business_status is "does it still
--    exist" (NULL there means Google never reached it — that is UNKNOWN, not
--    closed, which is why every read uses or=(is.null, neq.CLOSED_PERMANENTLY)).
--    Expect excluded_reason NULL and business_status NULL or 'OPERATIONAL'.
--    A hidden venue still gets a working dashboard — it just tells its owner
--    why nobody can see them.
--    select name, slug, city, excluded_reason, business_status
--      from public.venues where slug = 'example-venue-slug';

-- 3. Nobody has more access than you think. Expect a short, known list.
--    select u.email, v.name, v.city, vo.role, vo.created_at
--      from public.venue_owners vo
--      join auth.users u on u.id = vo.user_id
--      join public.venues v on v.id = vo.venue_id
--     order by vo.created_at desc;

-- 4. The door-code path is separate from this grant. If this venue also needs
--    the staff /validate screen, it needs a venue_secrets row too — that table
--    is deliberately unreadable by every client role.
--    select (select count(*) from public.venue_secrets s where s.venue_id = v.id)
--             as has_door_secret, v.name
--      from public.venues v where v.slug = 'example-venue-slug';

-- ═══════════════════════════════════════════════════════════════════
-- REVOKING (a manager leaves, a venue churns). Same idea, by hand.
-- ═══════════════════════════════════════════════════════════════════
--    delete from public.venue_owners vo
--     using auth.users u, public.venues v
--     where vo.user_id = u.id and vo.venue_id = v.id
--       and lower(u.email) = lower('owner@example.com')
--       and v.slug = 'example-venue-slug';
--
-- Revoking does NOT delete the events or promos they posted — those belong to
-- the venue, not to the person. It only stops them writing new ones, and stops
-- them hosting as the venue.
