import { NextResponse } from "next/server";
import { z } from "zod";
import { requireUser } from "@/lib/supabase/require-user";
import { ownerError } from "@/features/venue-owner/services/owner-errors";
import {
  toOwnerVenueDto,
  type OwnerVenueRow,
} from "@/features/venue-owner/services/owner-venue-dto";
import {
  summariseNight,
  startOfVenueDay,
  type OrderRow,
  type PassRow,
} from "@/features/venue-owner/services/owner-night-summary";

/**
 * GET /api/venue-owner/venues/[venueId] — everything one bar opens the
 * dashboard for, in a single call:
 *   · its catalogue row exactly as BarPass serves it (hours, photo, drink
 *     prices with their source, type, amenities) — and, when BarPass is NOT
 *     serving it, the reason why;
 *   · tonight's money and door count, in the venue's own timezone;
 *   · what is on at the venue: its own nights (`events`), its promos, and
 *     events promoters have anchored to it (`host_events`).
 *
 * Ownership is checked against `venue_owners` before anything privileged is
 * read. The service-role client bypasses RLS, so nothing here may be returned
 * without that check and without narrowing to an explicit DTO.
 */

const paramsSchema = z.object({ venueId: z.uuid() });

const EVENT_HORIZON_MS = 12 * 3600_000; // keep tonight's event visible after it starts

export async function GET(request: Request, { params }: { params: Promise<{ venueId: string }> }) {
  const auth = await requireUser(request);
  if (!auth.ok) return auth.response;
  const { supabase, user } = auth;

  const parsed = paramsSchema.safeParse(await params);
  if (!parsed.success) {
    return ownerError("invalid_venue_id", 422, "That venue id isn't a valid uuid.");
  }
  const venueId = parsed.data.venueId;

  const { data: link, error: linkError } = await supabase
    .from("venue_owners")
    .select("role")
    .eq("user_id", user.id)
    .eq("venue_id", venueId)
    .maybeSingle();
  if (linkError) {
    return ownerError("owner_lookup_failed", 503, linkError.message, { retryable: true });
  }
  if (!link) {
    // Deliberately the same answer whether the venue exists or the caller
    // simply doesn't own it — this endpoint must not be a catalogue oracle.
    return ownerError(
      "not_a_venue_owner",
      403,
      "This account isn't linked to that venue. BarPass ops provisions access.",
    );
  }

  const { data: venueRow, error: venueError } = await supabase
    .from("venues")
    .select("*")
    .eq("id", venueId)
    .maybeSingle();
  if (venueError) {
    return ownerError("venue_lookup_failed", 503, venueError.message, { retryable: true });
  }
  if (!venueRow) {
    return ownerError("venue_not_found", 404, "That venue is no longer in the catalogue.");
  }
  const venue = toOwnerVenueDto(venueRow as OwnerVenueRow);

  const dayStart = startOfVenueDay(new Date(), venue.timezone).toISOString();
  const horizon = new Date(Date.now() - EVENT_HORIZON_MS).toISOString();

  // `orders.vendor_id` and `passes.venue_id` are TEXT columns holding the
  // venue's uuid as a string (verified against live rows) — not the slug.
  const [ordersRes, passesRes, eventsRes, promosRes, hostEventsRes] = await Promise.all([
    supabase
      .from("orders")
      .select("id, total, status, created_at")
      .eq("vendor_id", venueId)
      .gte("created_at", dayStart),
    supabase
      .from("passes")
      .select("id, kind, quantity, amount, redeemed_at, created_at, source_order_id")
      .eq("venue_id", venueId)
      .gte("created_at", dayStart)
      .order("created_at", { ascending: false }),
    supabase
      .from("events")
      .select("id, title, description, starts_at, ends_at, cover_price")
      .eq("venue_id", venueId)
      .gte("starts_at", horizon)
      .order("starts_at", { ascending: true })
      .limit(50),
    supabase
      .from("promos")
      .select("id, title, description, starts_at, ends_at, discount_text")
      .eq("venue_id", venueId)
      .order("starts_at", { ascending: false })
      .limit(50),
    supabase
      .from("host_events")
      .select("id, title, starts_at, ends_at, status, host_type, host_display_name, cancelled_at")
      .eq("venue_id", venueId)
      .gte("starts_at", horizon)
      .order("starts_at", { ascending: true })
      .limit(50),
  ]);

  if (ordersRes.error || passesRes.error) {
    return ownerError(
      "stats_query_failed",
      503,
      ordersRes.error?.message ?? passesRes.error?.message ?? "Couldn't read tonight's numbers.",
      { retryable: true },
    );
  }

  const passes = (passesRes.data ?? []) as PassRow[];
  const tonight = summariseNight((ordersRes.data ?? []) as OrderRow[], passes);

  type HostEventRow = {
    id: string;
    title: string;
    starts_at: string;
    ends_at: string | null;
    status: string;
    host_type: string | null;
    host_display_name: string | null;
    cancelled_at: string | null;
  };

  // A failed sub-query says so instead of rendering as "nothing on tonight" —
  // an empty list and an unavailable list are different facts.
  const hostEvents = ((hostEventsRes.data ?? []) as HostEventRow[])
    .filter((e) => e.status === "published" && !e.cancelled_at)
    .map((e) => ({
      id: e.id,
      title: e.title,
      startsAt: e.starts_at,
      endsAt: e.ends_at,
      // The column defaults to 'promoter'; treat an absent value the same way,
      // because claiming to BE the venue is what has to be earned.
      hostType: e.host_type === "venue" ? "venue" : "promoter",
      hostName: e.host_display_name,
    }));

  return NextResponse.json({
    role: link.role ?? "owner",
    venue,
    tonight,
    recentPasses: passes.slice(0, 20).map((p) => ({
      id: p.id,
      kind: p.kind,
      quantity: p.quantity,
      amount: Number(p.amount),
      redeemedAt: p.redeemed_at,
      createdAt: p.created_at,
    })),
    events: (eventsRes.data ?? []).map((e) => ({
      id: e.id as string,
      title: e.title as string,
      description: (e.description as string | null) ?? "",
      startsAt: e.starts_at as string,
      endsAt: (e.ends_at as string | null) ?? null,
      coverPrice: (e.cover_price as number | null) ?? null,
    })),
    eventsUnavailable: !!eventsRes.error,
    promos: (promosRes.data ?? []).map((p) => ({
      id: p.id as string,
      title: p.title as string,
      description: (p.description as string | null) ?? null,
      startsAt: p.starts_at as string,
      endsAt: (p.ends_at as string | null) ?? null,
      discountText: (p.discount_text as string | null) ?? null,
    })),
    promosUnavailable: !!promosRes.error,
    hostEvents,
    hostEventsUnavailable: !!hostEventsRes.error,
  });
}

export const dynamic = "force-dynamic";

