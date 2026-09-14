import { NextResponse } from "next/server";
import { z } from "zod";
import type { SupabaseClient } from "@supabase/supabase-js";
import { checkRateLimit } from "@/lib/rate-limit";
import { requireUser } from "@/lib/supabase/require-user";
import {
  hostEventError,
  invalidJson,
  invalidPayload,
  readJson,
  rpcError,
  INVALID_JSON,
} from "@/features/host-events/services/host-event-errors";
import { toRsvpDto, type HostEventRsvpRow } from "@/features/host-events/services/host-event-dto";

/**
 * GET    /api/host-events/[id]/rsvp — the caller's own RSVPs for this event.
 * POST   /api/host-events/[id]/rsvp — take a spot on a tier.
 * DELETE /api/host-events/[id]/rsvp — release it back to the waiting list.
 * PATCH  /api/host-events/[id]/rsvp — flip the caller's own privacy flag.
 *
 * FREE ONLY, TODAY. Stripe is in test mode with charges_enabled = false, so
 * a tier with price_cents > 0 comes back 501 `paid_tier_not_enabled` from the
 * database itself — not from a check here that a future refactor could drop.
 * When payments land, this route charges first and then calls the same RPC
 * with the payment reference; the schema already has the columns.
 *
 * No 21+ gate here on purpose, unlike /api/passes: the college primitive this
 * implements is an 18+ door with a free RSVP list, and nothing here moves
 * money or grants a drink. The gate belongs on the paid path, at the charge,
 * exactly where requireAgeVerified21 already sits for passes.
 */

const rsvpSchema = z.object({ tierId: z.uuid() });
const releaseSchema = z.object({ rsvpId: z.uuid() });
const privacySchema = z.object({ rsvpId: z.uuid(), showOnAttendeeList: z.boolean() });

export async function GET(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const auth = await requireUser(request);
  if (!auth.ok) return auth.response;
  const { supabase, user } = auth;

  const { data, error } = await supabase
    .from("host_event_rsvps")
    .select("*")
    .eq("event_id", id)
    .eq("user_id", user.id)
    .order("created_at", { ascending: false });
  if (error) return hostEventError("read_failed", 500, error.message, { retryable: true });

  const now = new Date();
  return NextResponse.json({
    rsvps: ((data ?? []) as HostEventRsvpRow[]).map((r) => toRsvpDto(r, now)),
  });
}

export async function POST(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const auth = await requireUser(request);
  if (!auth.ok) return auth.response;
  const { supabase, user } = auth;

  // A free RSVP on a capped tier is a race worth hammering. The RPC is
  // already atomic under a row lock; this just keeps one client from
  // spending the whole tier's contention budget.
  const withinLimit = await checkRateLimit(`host-events:rsvp:${user.id}`, {
    maxRequests: 20,
    windowSeconds: 60,
  });
  if (!withinLimit) {
    return hostEventError("rate_limited", 429, "Slow down a moment and try again.", {
      retryable: true,
      retryAfterSeconds: 30,
    });
  }

  const body = await readJson(request);
  if (body === INVALID_JSON) return invalidJson();
  const parsed = rsvpSchema.safeParse(body);
  if (!parsed.success) return invalidPayload(parsed.error.issues[0]?.message);

  const belongs = await tierBelongsToEvent(supabase, parsed.data.tierId, id);
  if (!belongs) return hostEventError("tier_not_found", 404, "That ticket type doesn't exist.");

  const { data, error } = await supabase.rpc("host_event_rsvp", {
    p_user_id: user.id,
    p_tier_id: parsed.data.tierId,
  });
  if (error) return rpcError(error.message);

  const row = (Array.isArray(data) ? data[0] : data) as HostEventRsvpRow | null;
  if (!row) return hostEventError("rsvp_failed", 500, "The RSVP didn't come back.", { retryable: true });
  return NextResponse.json({ rsvp: toRsvpDto(row, new Date()) }, { status: 201 });
}

export async function DELETE(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const auth = await requireUser(request);
  if (!auth.ok) return auth.response;
  const { supabase, user } = auth;

  // Accepts ?rsvpId= or a JSON body — DELETE-with-body is awkward for some
  // clients (URLSession among them) and this costs nothing to support.
  const fromQuery = new URL(request.url).searchParams.get("rsvpId");
  const source = fromQuery ? { rsvpId: fromQuery } : await readJson(request);
  if (source === INVALID_JSON) return invalidJson();
  const parsed = releaseSchema.safeParse(source);
  if (!parsed.success) return invalidPayload(parsed.error.issues[0]?.message);

  const { data: existing } = await supabase
    .from("host_event_rsvps")
    .select("id, event_id, user_id")
    .eq("id", parsed.data.rsvpId)
    .eq("user_id", user.id)
    .maybeSingle();
  if (!existing || existing.event_id !== id) {
    return hostEventError("rsvp_not_found", 404, "No RSVP of yours matches that.");
  }

  const { data, error } = await supabase.rpc("host_event_release_rsvp", {
    p_user_id: user.id,
    p_rsvp_id: parsed.data.rsvpId,
  });
  if (error) return rpcError(error.message);

  const row = (Array.isArray(data) ? data[0] : data) as HostEventRsvpRow | null;
  return NextResponse.json({
    rsvp: row ? toRsvpDto(row, new Date()) : null,
    // The released seat is offered straight down the queue at face value —
    // no resale, no price change. That happens inside the RPC.
    releasedToWaitlist: true,
  });
}

export async function PATCH(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const auth = await requireUser(request);
  if (!auth.ok) return auth.response;
  const { supabase, user } = auth;

  const body = await readJson(request);
  if (body === INVALID_JSON) return invalidJson();
  const parsed = privacySchema.safeParse(body);
  if (!parsed.success) return invalidPayload(parsed.error.issues[0]?.message);

  const { data, error } = await supabase
    .from("host_event_rsvps")
    .update({ show_on_attendee_list: parsed.data.showOnAttendeeList })
    .eq("id", parsed.data.rsvpId)
    .eq("user_id", user.id)
    .eq("event_id", id)
    .select()
    .maybeSingle();
  if (error) return hostEventError("update_failed", 500, error.message, { retryable: true });
  if (!data) return hostEventError("rsvp_not_found", 404, "No RSVP of yours matches that.");

  return NextResponse.json({ rsvp: toRsvpDto(data as HostEventRsvpRow, new Date()) });
}

async function tierBelongsToEvent(
  supabase: SupabaseClient,
  tierId: string,
  eventId: string,
): Promise<boolean> {
  const { data } = await supabase
    .from("host_event_tiers")
    .select("id")
    .eq("id", tierId)
    .eq("event_id", eventId)
    .maybeSingle();
  return Boolean(data);
}
