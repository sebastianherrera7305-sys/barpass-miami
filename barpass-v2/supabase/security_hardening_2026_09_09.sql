-- Security hardening, 2026-09-09. Every item below was verified against the
-- live database or by reading the exact policy text — none is theoretical.
--
-- Idempotent, safe to re-run.

-- ═══════════════════════════════════════════════════════════════════
-- 1. TRIPS — anonymous scrape + member-to-creator takeover
-- ═══════════════════════════════════════════════════════════════════
-- VERIFIED 2026-09-09 against production: with only the public anon key
-- (which ships inside the iOS binary) a request to /rest/v1/trips returned
-- 2 of 3 trips INCLUDING their invite_code. A brand-new account then read a
-- code it had no business seeing, called redeem_trip_invite, and became a
-- member of a stranger's trip. Two separate defects:
--
--   a) trips_select had no `to` clause, so it applied to `anon` as well as
--      `authenticated` — an invite code is a credential and was readable
--      without logging in at all.
--   b) trips_update declares only USING and no WITH CHECK. Postgres then
--      reuses USING as the check, so a mere member passes it while setting
--      creator_id = auth.uid() — taking ownership, evicting everyone, and
--      unlocking trips_delete (creator-only). Chained with (a) that is a
--      full takeover of any non-private trip by anyone.

drop policy if exists trips_select on public.trips;
create policy trips_select on public.trips
    for select to authenticated using (
        auth.uid() = creator_id
        or auth.uid() = any(member_ids)
        or visibility <> 'private'
    );

drop policy if exists trips_insert on public.trips;
create policy trips_insert on public.trips
    for insert to authenticated with check (auth.uid() = creator_id);

-- WITH CHECK now stated explicitly. The trigger below is what actually pins
-- the sensitive fields; this keeps the post-update row inside the same
-- visibility rule so an update can't hide a trip from its own creator.
drop policy if exists trips_update on public.trips;
create policy trips_update on public.trips
    for update to authenticated
    using (auth.uid() = creator_id or auth.uid() = any(member_ids))
    with check (auth.uid() = creator_id or auth.uid() = any(member_ids));

drop policy if exists trips_delete on public.trips;
create policy trips_delete on public.trips
    for delete to authenticated using (auth.uid() = creator_id);

-- Fields a non-creator must never change. Silently restored rather than
-- raised on, except the member list, where a silent no-op would look like a
-- successful "remove someone" in the UI.
create or replace function public.protect_trip_ownership()
returns trigger language plpgsql security definer set search_path = public as $$
begin
    if auth.uid() is null then
        return new;                       -- service role / cron: unrestricted
    end if;
    if auth.uid() <> old.creator_id then
        new.creator_id      := old.creator_id;
        new.invite_code     := old.invite_code;
        new.co_organizer_ids := old.co_organizer_ids;
        -- A member may only add or remove THEMSELVES.
        if (select coalesce(array_agg(x order by x), '{}')
              from unnest(coalesce(new.member_ids, '{}')) x where x <> auth.uid())
           is distinct from
           (select coalesce(array_agg(x order by x), '{}')
              from unnest(coalesce(old.member_ids, '{}')) x where x <> auth.uid())
        then
            raise exception 'only the trip creator can change the member list';
        end if;
    end if;
    return new;
end;
$$;

drop trigger if exists trg_protect_trip_ownership on public.trips;
create trigger trg_protect_trip_ownership
    before update on public.trips
    for each row execute function public.protect_trip_ownership();

-- Discovery without handing out the credential. The app lists other people's
-- open trips from here; invite_code is simply not a column of this view, so
-- there is nothing to leak. security_invoker = false is deliberate and safe:
-- the view's own WHERE is the access rule, and it exposes no secret.
drop view if exists public.discoverable_trips;
create view public.discoverable_trips
with (security_invoker = false) as
select id, creator_id, title, destination_city, start_date, end_date,
       cover_image, visibility, status, member_ids, co_organizer_ids, stops
from public.trips
where visibility <> 'private';

revoke all on public.discoverable_trips from anon;
grant select on public.discoverable_trips to authenticated;

-- ═══════════════════════════════════════════════════════════════════
-- 2. CROWD REPORTS — public rows exposed a per-user venue-visit history
-- ═══════════════════════════════════════════════════════════════════
-- venue_age_reports and venue_price_reports are written at CHECK-OUT, so a
-- row is "user U was physically at venue V on date D". Both were
-- `for select to anon, authenticated using (true)` — the exact location
-- history the_grid.sql deliberately refuses to expose (venue_checkins is
-- owner-read-only, "never exposes a specific user's location"). Anyone with
-- the anon key could reconstruct where any user goes at night.
--
-- Nothing in the product reads these rows directly; the app consumes only
-- the aggregates (venue_price_stats, venue_age_effective). So: lock the base
-- tables to their owner and let the aggregates run as definer.

drop policy if exists "age reports are public" on public.venue_age_reports;
create policy "read own age reports" on public.venue_age_reports for select
    to authenticated using (user_id = auth.uid());

drop policy if exists "price reports are public" on public.venue_price_reports;
create policy "read own price reports" on public.venue_price_reports for select
    to authenticated using (user_id = auth.uid());

-- Aggregates stay public — they carry no user_id.
alter view public.venue_price_stats set (security_invoker = false);
alter view public.venue_age_effective set (security_invoker = false);
grant select on public.venue_price_stats to anon, authenticated;
grant select on public.venue_age_effective to anon, authenticated;

-- venue_media is intentionally public content, but the poster's user_id
-- doesn't need to be world-readable to render a photo grid. The app reads
-- id/venue_id/media_url/media_type/created_at; owner-only delete still works
-- because the DELETE policy compares user_id server-side.
revoke select (user_id) on public.venue_media from anon;

-- ═══════════════════════════════════════════════════════════════════
-- 3. CHAPTER CHAT — report any message in any chapter
-- ═══════════════════════════════════════════════════════════════════
-- report_chapter_message() took p_message_id on faith: no chapter check, no
-- ban check, unlike every other chapter RPC in that schema. Three accounts
-- could auto-hide any message in any chapter they never belonged to.

create or replace function public.report_chapter_message(p_message_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare
    v_chapter_id uuid;
    v_msg_chapter_id uuid;
begin
    select chapter_id into v_chapter_id from profiles where id = auth.uid();
    select chapter_id into v_msg_chapter_id from chapter_messages where id = p_message_id;
    if v_chapter_id is null or v_msg_chapter_id is null or v_chapter_id <> v_msg_chapter_id then
        raise exception 'not a member of this message''s chapter';
    end if;
    if exists (select 1 from chapter_bans
               where chapter_id = v_chapter_id and user_id = auth.uid()
                 and (expires_at is null or expires_at > now())) then
        raise exception 'banned from this chapter';
    end if;

    insert into chapter_message_reports (message_id, reporter_id, reason)
        values (p_message_id, auth.uid(), p_reason)
        on conflict (message_id, reporter_id) do nothing;

    update chapter_messages
       set report_count = (select count(*) from chapter_message_reports where message_id = p_message_id)
     where id = p_message_id;

    if (select report_count from chapter_messages where id = p_message_id) >= 3 then
        update chapter_messages set deleted_at = now()
         where id = p_message_id and deleted_at is null;
    end if;
end;
$$;

-- The direct-insert path the RPC is supposed to be the only door to.
drop policy if exists "report a message" on public.chapter_message_reports;
create policy "report a message" on public.chapter_message_reports for insert
    to authenticated with check (
        reporter_id = auth.uid()
        and exists (
            select 1 from public.chapter_messages m
            where m.id = message_id
              and m.chapter_id = (select chapter_id from public.profiles where id = auth.uid())
        )
    );

-- ═══════════════════════════════════════════════════════════════════
-- 4. PASS PRICING — a $0.01 wallet spend minted a real, redeemable pass
-- ═══════════════════════════════════════════════════════════════════
-- VERIFIED by reading src/app/api/passes/route.ts: the route derived the
-- pass amount straight from the payment source
-- (`verifiedAmount = Math.abs(Number(txn.amount))`) and never compared it to
-- a price, while /api/wallet/spend accepts any positive amount. Redemption
-- checks the code, the venue and the expiry — never the amount. So: spend a
-- cent, get a valid table pass for 20 people at the door.
--
-- This table is the server-side price the route now requires. It starts
-- EMPTY on purpose: with no row, /api/passes returns 409 price_not_configured
-- rather than minting anything. No price is invented here — a venue's real
-- prices get inserted when they're actually known.

create table if not exists public.venue_pass_prices (
    venue_id   text not null,
    kind       text not null check (kind in ('skip_line', 'table', 'ticket', 'drink')),
    unit_price numeric(10,2) not null check (unit_price >= 0),
    currency   text not null default 'USD',
    updated_at timestamptz not null default now(),
    primary key (venue_id, kind)
);

alter table public.venue_pass_prices enable row level security;

-- Readable so the app can show a price before checkout; writable only by the
-- service role (no policy = no client writes), same as venue_secrets.
drop policy if exists "pass prices are public" on public.venue_pass_prices;
create policy "pass prices are public" on public.venue_pass_prices for select
    to anon, authenticated using (true);
