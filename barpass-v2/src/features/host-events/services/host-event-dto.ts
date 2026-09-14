import { entryValidityState, salesState, tierAvailability } from "./host-event-rules";

/**
 * Explicit DTOs for everything the host-event routes return.
 *
 * These routes read with the service-role client, which bypasses RLS — so
 * the narrowing that RLS would have done has to happen here instead, by
 * listing the fields out. Nothing that identifies an attendee appears in a
 * public shape (see supabase/host_events_schema.sql §3 for why).
 */

export interface HostEventRow {
  id: string;
  host_id: string;
  venue_id: string;
  title: string;
  description: string;
  starts_at: string;
  ends_at: string | null;
  status: string;
  attendee_list_public: boolean;
  claim_window_minutes: number;
  cover_image_url: string | null;
  cancelled_at: string | null;
  created_at: string;
}

export interface HostEventTierRow {
  id: string;
  event_id: string;
  name: string;
  description: string | null;
  price_cents: number;
  quantity: number;
  claimed_count: number;
  sales_start_at: string;
  sales_end_at: string;
  entry_valid_from: string;
  entry_valid_until: string;
  sort_order: number;
}

export function toEventDto(row: HostEventRow, venue?: { name: string; slug: string } | null) {
  return {
    id: row.id,
    hostId: row.host_id,
    venue: {
      id: row.venue_id,
      name: venue?.name ?? null,
      slug: venue?.slug ?? null,
    },
    title: row.title,
    description: row.description,
    startsAt: row.starts_at,
    endsAt: row.ends_at,
    status: row.status,
    attendeeListPublic: row.attendee_list_public,
    claimWindowMinutes: row.claim_window_minutes,
    coverImageUrl: row.cover_image_url,
    cancelledAt: row.cancelled_at,
    createdAt: row.created_at,
  };
}

/**
 * `remaining` counts live waitlist offers against capacity, same as the
 * database does — a seat mid-claim is not a seat on sale. `activeOffers` is
 * passed in by the caller that already counted them; omitted it degrades to
 * "nobody is mid-claim", which is the correct answer for a tier with no queue.
 */
export function toTierDto(row: HostEventTierRow, now: Date, activeOffers = 0) {
  const { remaining, soldOut } = tierAvailability({
    quantity: row.quantity,
    claimedCount: row.claimed_count,
    activeOffers,
  });
  return {
    id: row.id,
    name: row.name,
    description: row.description,
    priceCents: row.price_cents,
    isFree: row.price_cents === 0,
    // Honest about the one thing that doesn't work yet, on every tier shape.
    purchasable: row.price_cents === 0,
    quantity: row.quantity,
    remaining,
    soldOut,
    salesStartAt: row.sales_start_at,
    salesEndAt: row.sales_end_at,
    salesState: salesState(
      { salesStartAt: row.sales_start_at, salesEndAt: row.sales_end_at },
      now,
    ),
    entryValidFrom: row.entry_valid_from,
    entryValidUntil: row.entry_valid_until,
    sortOrder: row.sort_order,
  };
}

export interface HostEventRsvpRow {
  id: string;
  event_id: string;
  tier_id: string;
  status: string;
  price_cents_paid: number;
  ticket_code: string;
  entry_valid_from: string;
  entry_valid_until: string;
  show_on_attendee_list: boolean;
  created_at: string;
}

export function toRsvpDto(row: HostEventRsvpRow, now: Date) {
  return {
    id: row.id,
    eventId: row.event_id,
    tierId: row.tier_id,
    status: row.status,
    priceCentsPaid: row.price_cents_paid,
    ticketCode: row.ticket_code,
    entryValidFrom: row.entry_valid_from,
    entryValidUntil: row.entry_valid_until,
    entryValidity: entryValidityState(row.entry_valid_from, row.entry_valid_until, now),
    showOnAttendeeList: row.show_on_attendee_list,
    createdAt: row.created_at,
  };
}

