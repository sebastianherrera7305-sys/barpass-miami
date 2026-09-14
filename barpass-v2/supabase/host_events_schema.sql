-- ─────────────────────────────────────────────────────────────────────────
-- BarPass V2 — HOST EVENTS: user-created events anchored to a verified venue,
-- tiered RSVP with sales + entry-validity windows, and a face-value waitlist.
--
-- Run in the Supabase SQL editor. Idempotent — safe to re-run.
--
-- WHY A NEW TABLE AND NOT `public.events`
-- ---------------------------------------
-- `public.events` is venue-operator content: ~1.8k rows synced/seeded for the
-- catalogue, readable by `anon` unconditionally ("events are public",
-- schema.sql), writable only by a provisioned `venue_owners` row
-- (venue_owner_events_promos.sql). It has no host identity, no lifecycle
-- (draft/cancelled), no capacity, and every consumer — the venue page, the
-- concierge digest, /api/events/live, the iOS app — reads it with the
-- assumption "this was put there by us or by the venue".
--
-- Host events are user-generated content: anyone with an account can create
-- one. Grafting them onto `events` would mean (a) a nullable `host_id` that
-- must stay NULL on 1.8k existing rows, (b) loosening the unconditional anon
-- read policy to account for drafts and cancellations, and (c) every existing
-- consumer silently starting to serve unmoderated user content the day the
-- column lands. That is precisely the Posh failure mode this product is
-- differentiating against. `chapter_events.sql` already made this same call
-- for the same reason; this follows that precedent.
--
-- What IS shared with `events`: the venue anchor. `venue_id` is NOT NULL and
-- REFERENCES public.venues(id). There is no free-text location column, by
-- design — the verified catalogue is the differentiator.
--
-- PAYMENTS ARE NOT WIRED (2026-09-14)
-- -----------------------------------
-- Stripe is in test mode with charges_enabled = false. `price_cents` exists,
-- and the paid path is schema-complete (payment_ref / payment_provider on the
-- RSVP row), but every RPC below REFUSES a tier with price_cents > 0 with
-- `paid_tier_not_enabled`. Free RSVP (price_cents = 0) works end to end.
-- Turning paid on later is: charge, then call the same RPC with a verified
-- payment reference. No schema change.
-- ─────────────────────────────────────────────────────────────────────────


-- ═══════════════════════════════════════════════════════════════════
-- 1. TABLES
-- ═══════════════════════════════════════════════════════════════════

create table if not exists public.host_events (
  id uuid primary key default gen_random_uuid(),
  host_id uuid not null references auth.users(id) on delete cascade,
  -- The anchor. NOT NULL, FK to the verified catalogue. No free-text venue.
  venue_id uuid not null references public.venues(id) on delete restrict,
  title text not null check (char_length(trim(title)) between 1 and 120),
  description text not null default '' check (char_length(description) <= 2000),
  starts_at timestamptz not null,
  ends_at timestamptz,
  status text not null default 'draft'
    check (status in ('draft', 'published', 'cancelled')),
  -- The organiser's master switch over the attendee list, matching Posh's own
  -- privacy model: the organiser decides whether the list exists publicly at
  -- all; each attendee then decides whether THEY appear in it. Both must be
  -- true for a row to be visible to anyone but the host.
  attendee_list_public boolean not null default false,
  -- How long a waitlist offer stays claimable before it passes down the queue.
  claim_window_minutes int not null default 30
    check (claim_window_minutes between 5 and 1440),
  cover_image_url text,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at is null or ends_at > starts_at)
);

create table if not exists public.host_event_tiers (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.host_events(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 60),
  description text check (description is null or char_length(description) <= 300),
  -- 0 = free RSVP (the college primitive: "Free RSVP for LADIES"). > 0 is
  -- schema-complete but refused at runtime until Stripe is live.
  price_cents int not null default 0 check (price_cents >= 0),
  quantity int not null check (quantity between 1 and 100000),
  -- Maintained only by the RPCs below, never by a client (no write policy).
  claimed_count int not null default 0 check (claimed_count >= 0),
  -- SALES window: when this tier can be claimed at all.
  sales_start_at timestamptz not null,
  sales_end_at timestamptz not null,
  -- ENTRY VALIDITY window: the "valid 10–11 PM" part. Holding the RSVP does
  -- not mean you can walk in whenever; this is the door's window.
  entry_valid_from timestamptz not null,
  entry_valid_until timestamptz not null,
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  check (sales_end_at > sales_start_at),
  check (entry_valid_until > entry_valid_from),
  check (claimed_count <= quantity)
);

create table if not exists public.host_event_rsvps (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.host_events(id) on delete cascade,
  tier_id uuid not null references public.host_event_tiers(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'confirmed'
    check (status in ('confirmed', 'released', 'cancelled_by_host')),
  -- What was actually collected. 0 today, always.
  price_cents_paid int not null default 0 check (price_cents_paid >= 0),
  -- The paid path's landing spot. Null for free RSVP; a Stripe PaymentIntent
  -- id (or a wallet transaction id) once payments are live.
  payment_provider text check (payment_provider is null or payment_provider in ('stripe', 'wallet')),
  payment_ref text,
  ticket_code text not null unique,
  -- Validity is SNAPSHOT at claim time, not read live off the tier. A host
  -- editing a tier's window after tickets went out must not silently
  -- invalidate (or extend) a pass someone already holds.
  entry_valid_from timestamptz not null,
  entry_valid_until timestamptz not null,
  -- The attendee's own privacy flag. Independent of the host's master switch.
  show_on_attendee_list boolean not null default true,
  created_at timestamptz not null default now(),
  released_at timestamptz
);

create table if not exists public.host_event_waitlist (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.host_events(id) on delete cascade,
  tier_id uuid not null references public.host_event_tiers(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  -- Queue order. Strictly join time, tie-broken by id — no priority, no
  -- paying to skip. That is the point of the DICE mechanic.
  joined_at timestamptz not null default now(),
  state text not null default 'waiting'
    check (state in ('waiting', 'offered', 'claimed', 'expired', 'left')),
  offered_at timestamptz,
  claim_expires_at timestamptz,
  claimed_rsvp_id uuid references public.host_event_rsvps(id) on delete set null,
  check (state <> 'offered' or (offered_at is not null and claim_expires_at is not null))
);

-- Columns added after the first cut of this file land here so an existing
-- database picks them up on a re-run (create table if not exists would skip).
alter table public.host_events        add column if not exists cover_image_url text;
alter table public.host_event_tiers   add column if not exists sort_order int not null default 0;
alter table public.host_event_rsvps   add column if not exists payment_provider text;
alter table public.host_event_rsvps   add column if not exists payment_ref text;


-- ═══════════════════════════════════════════════════════════════════
-- 2. INDEXES / UNIQUENESS
-- ═══════════════════════════════════════════════════════════════════

create index if not exists host_events_venue_idx   on public.host_events (venue_id, starts_at);
create index if not exists host_events_host_idx    on public.host_events (host_id, starts_at desc);
create index if not exists host_events_public_idx  on public.host_events (starts_at)
  where status = 'published';
create index if not exists host_event_tiers_event_idx on public.host_event_tiers (event_id, sort_order);
create index if not exists host_event_rsvps_user_idx  on public.host_event_rsvps (user_id, created_at desc);
create index if not exists host_event_rsvps_event_idx on public.host_event_rsvps (event_id, status);

-- One live RSVP per user per tier. Partial, so a user who RELEASED a spot can
-- legitimately take one again later (which is exactly what the waitlist
-- mechanic hands back to them).
create unique index if not exists host_event_rsvps_one_per_user_per_tier
  on public.host_event_rsvps (tier_id, user_id)
  where status = 'confirmed';

-- One live queue entry per user per tier, for the same reason.
create unique index if not exists host_event_waitlist_one_per_user_per_tier
  on public.host_event_waitlist (tier_id, user_id)
  where state in ('waiting', 'offered');

-- The queue read path: earliest joiner first.
create index if not exists host_event_waitlist_queue_idx
  on public.host_event_waitlist (tier_id, joined_at, id)
  where state = 'waiting';
create index if not exists host_event_waitlist_offers_idx
  on public.host_event_waitlist (claim_expires_at)
  where state = 'offered';
create index if not exists host_event_waitlist_user_idx
  on public.host_event_waitlist (user_id, joined_at desc);


-- ═══════════════════════════════════════════════════════════════════
-- 3. RLS
-- ═══════════════════════════════════════════════════════════════════
-- The rule that governs everything below: NOTHING that ties a user to a
-- venue on a date is readable by `anon`. That is the venue_media.user_id
-- incident (anon could reconstruct a person's location history) and it is
-- why host_event_rsvps and host_event_waitlist have NO anon policy at all —
-- not even a filtered one. The public attendee list is served exclusively by
-- a SECURITY DEFINER function that is revoked from anon.

alter table public.host_events         enable row level security;
alter table public.host_event_tiers    enable row level security;
alter table public.host_event_rsvps    enable row level security;
alter table public.host_event_waitlist enable row level security;

-- ── host_events ──────────────────────────────────────────────────
-- A published event is a public listing; host_id is the organiser of that
-- public listing (the same information Posh/DICE print on the flyer), not
-- private behaviour. Drafts and cancelled events are host-only.
drop policy if exists "published host events are public" on public.host_events;
create policy "published host events are public"
  on public.host_events for select
  to anon, authenticated
  using (status = 'published');

drop policy if exists "hosts read own host events" on public.host_events;
create policy "hosts read own host events"
  on public.host_events for select
  to authenticated
  using (auth.uid() = host_id);

drop policy if exists "hosts create own host events" on public.host_events;
create policy "hosts create own host events"
  on public.host_events for insert
  to authenticated
  with check (auth.uid() = host_id);

-- USING *and* WITH CHECK, both stated. A policy with only USING has its
-- USING clause reused as the check, which is how trips_update let a member
-- reassign creator_id to themselves (security_hardening_2026_09_09.sql).
drop policy if exists "hosts update own host events" on public.host_events;
create policy "hosts update own host events"
  on public.host_events for update
  to authenticated
  using (auth.uid() = host_id)
  with check (auth.uid() = host_id);

drop policy if exists "hosts delete own host events" on public.host_events;
create policy "hosts delete own host events"
  on public.host_events for delete
  to authenticated
  using (auth.uid() = host_id and status = 'draft');

-- host_id is pinned for the lifetime of the row: an UPDATE cannot hand the
-- event to someone else, and cannot be used to steal one.
create or replace function public.protect_host_event_owner()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then
    return new;                       -- service role: unrestricted
  end if;
  new.host_id := old.host_id;
  new.venue_id := old.venue_id;       -- re-anchoring a live event is not an edit
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists protect_host_event_owner_trigger on public.host_events;
create trigger protect_host_event_owner_trigger
  before update on public.host_events
  for each row execute function public.protect_host_event_owner();

-- ── host_event_tiers ─────────────────────────────────────────────
-- Tiers of a published event are public (prices and windows are the listing).
drop policy if exists "tiers of published events are public" on public.host_event_tiers;
create policy "tiers of published events are public"
  on public.host_event_tiers for select
  to anon, authenticated
  using (exists (
    select 1 from public.host_events e
    where e.id = host_event_tiers.event_id and e.status = 'published'
  ));

drop policy if exists "hosts read own tiers" on public.host_event_tiers;
create policy "hosts read own tiers"
  on public.host_event_tiers for select
  to authenticated
  using (exists (
    select 1 from public.host_events e
    where e.id = host_event_tiers.event_id and e.host_id = auth.uid()
  ));

drop policy if exists "hosts write own tiers" on public.host_event_tiers;
create policy "hosts write own tiers"
  on public.host_event_tiers for insert
  to authenticated
  with check (exists (
    select 1 from public.host_events e
    where e.id = host_event_tiers.event_id and e.host_id = auth.uid()
  ));

drop policy if exists "hosts update own tiers" on public.host_event_tiers;
create policy "hosts update own tiers"
  on public.host_event_tiers for update
  to authenticated
  using (exists (
    select 1 from public.host_events e
    where e.id = host_event_tiers.event_id and e.host_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.host_events e
    where e.id = host_event_tiers.event_id and e.host_id = auth.uid()
  ));

drop policy if exists "hosts delete unclaimed tiers" on public.host_event_tiers;
create policy "hosts delete unclaimed tiers"
  on public.host_event_tiers for delete
  to authenticated
  using (
    claimed_count = 0
    and exists (
      select 1 from public.host_events e
      where e.id = host_event_tiers.event_id and e.host_id = auth.uid()
    )
  );

-- claimed_count is capacity accounting, not host-editable content. A client
-- UPDATE (the host editing a tier name) must not be able to move it.
create or replace function public.protect_tier_claimed_count()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then
    return new;                       -- service role / the RPCs below
  end if;
  new.claimed_count := old.claimed_count;
  new.event_id := old.event_id;
  return new;
end;
$$;

drop trigger if exists protect_tier_claimed_count_trigger on public.host_event_tiers;
create trigger protect_tier_claimed_count_trigger
  before update on public.host_event_tiers
  for each row execute function public.protect_tier_claimed_count();

-- ── host_event_rsvps ─────────────────────────────────────────────
-- Own rows only. No anon policy. Hosts do NOT get a blanket SELECT policy
-- here either — they read their guest list through host_event_attendees(),
-- which is one auditable surface instead of a second identity-bearing one.
drop policy if exists "read own rsvps" on public.host_event_rsvps;
create policy "read own rsvps"
  on public.host_event_rsvps for select
  to authenticated
  using (auth.uid() = user_id);

-- The one thing an attendee may change directly: their own privacy flag.
-- Everything else (status, price, ticket code, validity) is RPC-only.
drop policy if exists "update own rsvp privacy flag" on public.host_event_rsvps;
create policy "update own rsvp privacy flag"
  on public.host_event_rsvps for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create or replace function public.protect_rsvp_fields()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then
    return new;                       -- service role / the RPCs below
  end if;
  new.event_id          := old.event_id;
  new.tier_id           := old.tier_id;
  new.user_id           := old.user_id;
  new.status            := old.status;
  new.price_cents_paid  := old.price_cents_paid;
  new.payment_provider  := old.payment_provider;
  new.payment_ref       := old.payment_ref;
  new.ticket_code       := old.ticket_code;
  new.entry_valid_from  := old.entry_valid_from;
  new.entry_valid_until := old.entry_valid_until;
  new.released_at       := old.released_at;
  return new;                         -- only show_on_attendee_list survives
end;
$$;

drop trigger if exists protect_rsvp_fields_trigger on public.host_event_rsvps;
create trigger protect_rsvp_fields_trigger
  before update on public.host_event_rsvps
  for each row execute function public.protect_rsvp_fields();

-- No INSERT or DELETE policy at all: an RSVP is minted only by
-- host_event_rsvp() / host_event_claim_offer(), which is what makes
-- capacity, the sales window and the free-only rule unforgeable.

-- ── host_event_waitlist ──────────────────────────────────────────
-- Own rows only. No anon policy, no client writes — position in a queue is
-- exactly the kind of thing that must not be self-assignable.
drop policy if exists "read own waitlist entries" on public.host_event_waitlist;
create policy "read own waitlist entries"
  on public.host_event_waitlist for select
  to authenticated
  using (auth.uid() = user_id);


-- ═══════════════════════════════════════════════════════════════════
-- 4. RPCs — the only writers of RSVPs, waitlist and claimed_count
-- ═══════════════════════════════════════════════════════════════════
-- Same shape as adjust_wallet_balance: SECURITY DEFINER, takes p_user_id
-- explicitly, EXECUTE revoked from anon AND authenticated (section 5), so
-- only the service role — i.e. an API route that has already run
-- requireUser() — can call them. auth.uid() is null under the service role,
-- which is why the caller is a parameter and never inferred.
--
-- Errors are raised with a machine-readable message the routes map to HTTP
-- statuses: event_not_found, tier_not_found, event_not_published,
-- event_cancelled, sales_not_open, sales_closed, paid_tier_not_enabled,
-- already_rsvped, sold_out, not_sold_out, already_waitlisted, rsvp_not_found,
-- offer_not_found, offer_expired.

create or replace function public.host_event_generate_ticket_code()
returns text language plpgsql as $$
declare
  v_code text;
begin
  for i in 1..8 loop
    v_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12));
    if not exists (select 1 from public.host_event_rsvps where ticket_code = v_code) then
      return v_code;
    end if;
  end loop;
  raise exception 'ticket_code_generation_failed';
end;
$$;

-- Expires stale offers on one tier and walks the queue down as far as
-- available capacity allows. Called at the start of every mutating RPC, so
-- the queue is always swept lazily by real traffic; a cron can also call
-- host_event_sweep_waitlist() but nothing depends on one running.
create or replace function public.host_event_offer_next(p_tier_id uuid)
returns int language plpgsql security definer set search_path = public as $$
declare
  v_tier public.host_event_tiers%rowtype;
  v_window int;
  v_active_offers int;
  v_available int;
  v_next public.host_event_waitlist%rowtype;
  v_offered int := 0;
begin
  select * into v_tier from public.host_event_tiers where id = p_tier_id for update;
  if not found then
    return 0;
  end if;

  select claim_window_minutes into v_window
    from public.host_events where id = v_tier.event_id;

  -- 1. Anything whose claim window elapsed loses the spot. It does not go
  --    back to "waiting" — it drops out and the offer moves down the queue.
  update public.host_event_waitlist
     set state = 'expired'
   where tier_id = p_tier_id
     and state = 'offered'
     and claim_expires_at <= now();

  -- 2. An outstanding offer RESERVES a spot — otherwise two people could be
  --    offered the same released seat and one would be told "sold out"
  --    after being told it was theirs.
  select count(*) into v_active_offers
    from public.host_event_waitlist
   where tier_id = p_tier_id and state = 'offered';

  v_available := v_tier.quantity - v_tier.claimed_count - v_active_offers;

  -- 3. Sales must still be open, and the event still live, or an offer would
  --    be unclaimable the moment it was made.
  if not exists (
    select 1 from public.host_events e
    where e.id = v_tier.event_id and e.status = 'published' and e.cancelled_at is null
  ) or now() >= v_tier.sales_end_at then
    return 0;
  end if;

  while v_available > 0 loop
    select * into v_next
      from public.host_event_waitlist
     where tier_id = p_tier_id and state = 'waiting'
     order by joined_at asc, id asc
     limit 1
     for update skip locked;
    exit when not found;

    update public.host_event_waitlist
       set state = 'offered',
           offered_at = now(),
           claim_expires_at = now() + make_interval(mins => coalesce(v_window, 30))
     where id = v_next.id;

    v_available := v_available - 1;
    v_offered := v_offered + 1;
  end loop;

  return v_offered;
end;
$$;

-- Free RSVP. The whole point of the file.
create or replace function public.host_event_rsvp(p_user_id uuid, p_tier_id uuid)
returns public.host_event_rsvps
language plpgsql security definer set search_path = public as $$
declare
  v_tier public.host_event_tiers%rowtype;
  v_event public.host_events%rowtype;
  v_rsvp public.host_event_rsvps%rowtype;
begin
  select * into v_tier from public.host_event_tiers where id = p_tier_id for update;
  if not found then raise exception 'tier_not_found'; end if;

  select * into v_event from public.host_events where id = v_tier.event_id;
  if not found then raise exception 'event_not_found'; end if;
  if v_event.cancelled_at is not null or v_event.status = 'cancelled' then
    raise exception 'event_cancelled';
  end if;
  if v_event.status <> 'published' then raise exception 'event_not_published'; end if;

  if now() < v_tier.sales_start_at then raise exception 'sales_not_open'; end if;
  if now() >= v_tier.sales_end_at  then raise exception 'sales_closed';   end if;

  -- Stripe charges_enabled = false. Refusing is the honest answer.
  if v_tier.price_cents > 0 then raise exception 'paid_tier_not_enabled'; end if;

  if exists (
    select 1 from public.host_event_rsvps
    where tier_id = p_tier_id and user_id = p_user_id and status = 'confirmed'
  ) then
    raise exception 'already_rsvped';
  end if;

  -- Outstanding offers hold real seats; count them against capacity so a
  -- walk-up can't take the seat a waitlister is mid-claim on.
  if v_tier.claimed_count + (
       select count(*) from public.host_event_waitlist
       where tier_id = p_tier_id and state = 'offered' and claim_expires_at > now()
     ) >= v_tier.quantity then
    raise exception 'sold_out';
  end if;

  update public.host_event_tiers
     set claimed_count = claimed_count + 1
   where id = p_tier_id;

  insert into public.host_event_rsvps (
    event_id, tier_id, user_id, price_cents_paid, ticket_code,
    entry_valid_from, entry_valid_until
  ) values (
    v_tier.event_id, p_tier_id, p_user_id, 0, public.host_event_generate_ticket_code(),
    v_tier.entry_valid_from, v_tier.entry_valid_until
  ) returning * into v_rsvp;

  -- A user leaving the queue because they got in the front door.
  update public.host_event_waitlist
     set state = 'left'
   where tier_id = p_tier_id and user_id = p_user_id and state in ('waiting', 'offered');

  return v_rsvp;
end;
$$;

-- Releasing a spot: the DICE mechanic. The seat goes back to the queue at
-- the same price, never to a resale market.
create or replace function public.host_event_release_rsvp(p_user_id uuid, p_rsvp_id uuid)
returns public.host_event_rsvps
language plpgsql security definer set search_path = public as $$
declare
  v_rsvp public.host_event_rsvps%rowtype;
begin
  select * into v_rsvp from public.host_event_rsvps
   where id = p_rsvp_id and user_id = p_user_id for update;
  if not found then raise exception 'rsvp_not_found'; end if;
  if v_rsvp.status <> 'confirmed' then raise exception 'rsvp_not_confirmed'; end if;

  update public.host_event_rsvps
     set status = 'released', released_at = now()
   where id = p_rsvp_id
  returning * into v_rsvp;

  update public.host_event_tiers
     set claimed_count = greatest(claimed_count - 1, 0)
   where id = v_rsvp.tier_id;

  perform public.host_event_offer_next(v_rsvp.tier_id);
  return v_rsvp;
end;
$$;

create or replace function public.host_event_join_waitlist(p_user_id uuid, p_tier_id uuid)
returns public.host_event_waitlist
language plpgsql security definer set search_path = public as $$
declare
  v_tier public.host_event_tiers%rowtype;
  v_event public.host_events%rowtype;
  v_entry public.host_event_waitlist%rowtype;
begin
  select * into v_tier from public.host_event_tiers where id = p_tier_id for update;
  if not found then raise exception 'tier_not_found'; end if;

  select * into v_event from public.host_events where id = v_tier.event_id;
  if v_event.status <> 'published' or v_event.cancelled_at is not null then
    raise exception 'event_not_published';
  end if;
  if now() >= v_tier.sales_end_at then raise exception 'sales_closed'; end if;

  if exists (
    select 1 from public.host_event_rsvps
    where tier_id = p_tier_id and user_id = p_user_id and status = 'confirmed'
  ) then
    raise exception 'already_rsvped';
  end if;

  if exists (
    select 1 from public.host_event_waitlist
    where tier_id = p_tier_id and user_id = p_user_id and state in ('waiting', 'offered')
  ) then
    raise exception 'already_waitlisted';
  end if;

  -- A queue for a tier that isn't full would be a lie about scarcity.
  if v_tier.claimed_count + (
       select count(*) from public.host_event_waitlist
       where tier_id = p_tier_id and state = 'offered' and claim_expires_at > now()
     ) < v_tier.quantity then
    raise exception 'not_sold_out';
  end if;

  insert into public.host_event_waitlist (event_id, tier_id, user_id)
  values (v_tier.event_id, p_tier_id, p_user_id)
  returning * into v_entry;

  -- Sweeps expired offers; may immediately offer this person the spot if an
  -- earlier offer just lapsed.
  perform public.host_event_offer_next(p_tier_id);

  select * into v_entry from public.host_event_waitlist where id = v_entry.id;
  return v_entry;
end;
$$;

create or replace function public.host_event_leave_waitlist(p_user_id uuid, p_tier_id uuid)
returns public.host_event_waitlist
language plpgsql security definer set search_path = public as $$
declare
  v_entry public.host_event_waitlist%rowtype;
begin
  update public.host_event_waitlist
     set state = 'left'
   where tier_id = p_tier_id and user_id = p_user_id and state in ('waiting', 'offered')
  returning * into v_entry;
  if not found then raise exception 'waitlist_entry_not_found'; end if;

  -- Leaving mid-offer frees the seat it was reserving.
  perform public.host_event_offer_next(p_tier_id);
  return v_entry;
end;
$$;

create or replace function public.host_event_claim_offer(p_user_id uuid, p_waitlist_id uuid)
returns public.host_event_rsvps
language plpgsql security definer set search_path = public as $$
declare
  v_entry public.host_event_waitlist%rowtype;
  v_tier public.host_event_tiers%rowtype;
  v_rsvp public.host_event_rsvps%rowtype;
begin
  select * into v_entry from public.host_event_waitlist
   where id = p_waitlist_id and user_id = p_user_id for update;
  if not found then raise exception 'offer_not_found'; end if;
  if v_entry.state <> 'offered' then raise exception 'offer_not_found'; end if;

  if v_entry.claim_expires_at <= now() then
    update public.host_event_waitlist set state = 'expired' where id = p_waitlist_id;
    perform public.host_event_offer_next(v_entry.tier_id);
    raise exception 'offer_expired';
  end if;

  select * into v_tier from public.host_event_tiers where id = v_entry.tier_id for update;
  -- Face value, always — the offer carries the tier's own price, and a paid
  -- one is still refused until Stripe is live.
  if v_tier.price_cents > 0 then raise exception 'paid_tier_not_enabled'; end if;

  update public.host_event_tiers set claimed_count = claimed_count + 1 where id = v_tier.id;

  insert into public.host_event_rsvps (
    event_id, tier_id, user_id, price_cents_paid, ticket_code,
    entry_valid_from, entry_valid_until
  ) values (
    v_tier.event_id, v_tier.id, p_user_id, 0, public.host_event_generate_ticket_code(),
    v_tier.entry_valid_from, v_tier.entry_valid_until
  ) returning * into v_rsvp;

  update public.host_event_waitlist
     set state = 'claimed', claimed_rsvp_id = v_rsvp.id
   where id = p_waitlist_id;

  return v_rsvp;
end;
$$;

-- Standalone sweep, for a cron or a read path that wants a fresh queue.
create or replace function public.host_event_sweep_waitlist()
returns int language plpgsql security definer set search_path = public as $$
declare
  r record;
  v_total int := 0;
begin
  for r in
    select distinct tier_id from public.host_event_waitlist
    where state in ('waiting', 'offered')
  loop
    v_total := v_total + public.host_event_offer_next(r.tier_id);
  end loop;
  return v_total;
end;
$$;

-- ── "Who's going" ────────────────────────────────────────────────
-- BOTH switches must be on for a non-host to see a row: the host's
-- attendee_list_public (the organiser holds the master switch, per Posh's own
-- privacy documentation) AND the attendee's own show_on_attendee_list.
-- The host sees every confirmed attendee regardless — they run the door —
-- with hidden_from_public flagged so a UI can say so.
create or replace function public.host_event_attendees(p_user_id uuid, p_event_id uuid)
returns table (
  user_id uuid,
  display_name text,
  avatar_url text,
  tier_name text,
  hidden_from_public boolean
)
language plpgsql security definer set search_path = public as $$
declare
  v_event public.host_events%rowtype;
  v_is_host boolean;
begin
  select * into v_event from public.host_events where id = p_event_id;
  if not found then raise exception 'event_not_found'; end if;

  v_is_host := (p_user_id is not null and p_user_id = v_event.host_id);

  if not v_is_host then
    if v_event.status <> 'published' then raise exception 'event_not_published'; end if;
    if not v_event.attendee_list_public then raise exception 'attendee_list_private'; end if;
  end if;

  return query
    select r.user_id,
           coalesce(p.display_name, 'Nightlifer') as display_name,
           p.avatar_url,
           t.name as tier_name,
           (not r.show_on_attendee_list) as hidden_from_public
      from public.host_event_rsvps r
      join public.host_event_tiers t on t.id = r.tier_id
      left join public.profiles p on p.id = r.user_id
     where r.event_id = p_event_id
       and r.status = 'confirmed'
       and (v_is_host or r.show_on_attendee_list)
     order by r.created_at asc;
end;
$$;


-- ═══════════════════════════════════════════════════════════════════
-- 5. EXECUTE PRIVILEGES
-- ═══════════════════════════════════════════════════════════════════
-- Supabase's default privileges grant EXECUTE to anon AND authenticated at
-- creation time, and those are explicit grants that revoking from PUBLIC does
-- NOT remove (lock_down_rpc_execute.sql learned this the hard way). Revoke
-- from all three by name. Every function here is service-role only: the API
-- routes call them after requireUser(), and the caller is always a parameter.
do $$
declare r record;
begin
  for r in
    select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in (
      'host_event_rsvp', 'host_event_release_rsvp', 'host_event_join_waitlist',
      'host_event_leave_waitlist', 'host_event_claim_offer', 'host_event_offer_next',
      'host_event_sweep_waitlist', 'host_event_attendees',
      'host_event_generate_ticket_code', 'protect_host_event_owner',
      'protect_tier_claimed_count', 'protect_rsvp_fields'
    )
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', r.oid::regprocedure);
  end loop;
end $$;


-- ═══════════════════════════════════════════════════════════════════
-- 6. VERIFICATION QUERIES  (run these after the migration)
-- ═══════════════════════════════════════════════════════════════════
--
-- 6.1 — RLS is on for all four tables. Expect 4 rows, rowsecurity = true.
--
--   select relname, relrowsecurity
--     from pg_class
--    where relnamespace = 'public'::regnamespace
--      and relname in ('host_events','host_event_tiers','host_event_rsvps','host_event_waitlist');
--
-- 6.2 — Anon can never read an identity-bearing row. Expect 0 rows: no
--       policy on the rsvp/waitlist tables mentions the anon role.
--
--   select p.polname, c.relname, pg_get_expr(p.polqual, p.polrelid) as using_expr,
--          array(select rolname from pg_roles where oid = any(p.polroles)) as roles
--     from pg_policy p join pg_class c on c.oid = p.polrelid
--    where c.relname in ('host_event_rsvps','host_event_waitlist')
--      and 'anon' = any(array(select rolname from pg_roles where oid = any(p.polroles)));
--
--       And the live check, from a shell with the ANON key (should return []):
--         curl -s "$URL/rest/v1/host_event_rsvps?select=user_id" -H "apikey: $ANON"
--         curl -s "$URL/rest/v1/host_event_waitlist?select=user_id" -H "apikey: $ANON"
--
-- 6.3 — Every RPC is service-role only. Expect 0 rows.
--
--   select p.proname,
--          has_function_privilege('anon', p.oid, 'execute') as anon_can,
--          has_function_privilege('authenticated', p.oid, 'execute') as auth_can
--     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'public' and p.proname like 'host_event%'
--      and (has_function_privilege('anon', p.oid, 'execute')
--           or has_function_privilege('authenticated', p.oid, 'execute'));
--
-- 6.4 — Double-RSVP is impossible. Expect 0 rows.
--
--   select tier_id, user_id, count(*)
--     from public.host_event_rsvps where status = 'confirmed'
--    group by 1,2 having count(*) > 1;
--
-- 6.5 — Capacity accounting never drifts from reality. Expect 0 rows.
--
--   select t.id, t.name, t.quantity, t.claimed_count,
--          (select count(*) from public.host_event_rsvps r
--            where r.tier_id = t.id and r.status = 'confirmed') as real_confirmed
--     from public.host_event_tiers t
--    where t.claimed_count <> (select count(*) from public.host_event_rsvps r
--                               where r.tier_id = t.id and r.status = 'confirmed')
--       or t.claimed_count > t.quantity;
--
-- 6.6 — No live queue entry duplicates, and no offer without a window.
--       Expect 0 rows from both.
--
--   select tier_id, user_id, count(*) from public.host_event_waitlist
--    where state in ('waiting','offered') group by 1,2 having count(*) > 1;
--
--   select id from public.host_event_waitlist
--    where state = 'offered' and (offered_at is null or claim_expires_at is null);
--
-- 6.7 — Every event is anchored to a real venue. Expect 0 rows.
--
--   select e.id from public.host_events e
--    left join public.venues v on v.id = e.venue_id where v.id is null;
--
-- 6.8 — Nothing was ever charged. Expect 0 rows while Stripe is off.
--
--   select id, price_cents_paid, payment_ref from public.host_event_rsvps
--    where price_cents_paid > 0 or payment_ref is not null;
--
-- 6.9 — Windows are coherent on every tier. Expect 0 rows.
--
--   select id, name from public.host_event_tiers
--    where sales_end_at <= sales_start_at or entry_valid_until <= entry_valid_from;
