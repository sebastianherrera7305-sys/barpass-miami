import { NextResponse } from "next/server";
import { z } from "zod";
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
 * POST /api/host-events/[id]/waitlist/claim
 * Body: { waitlistId }
 *
 * Takes a spot that was offered down the queue, at the tier's own price. The
 * claim window is enforced in the database, not here — an expired claim is
 * marked expired and re-offered to the next person inside the same
 * transaction, so there is no window where a seat is held by nobody.
 *
 * A paid tier still refuses with 501: releasing a paid spot must be a refund
 * plus a charge, and nothing can be charged while Stripe sits at
 * charges_enabled = false.
 */

const claimSchema = z.object({ waitlistId: z.uuid() });

export async function POST(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const auth = await requireUser(request);
  if (!auth.ok) return auth.response;
  const { supabase, user } = auth;

  const body = await readJson(request);
  if (body === INVALID_JSON) return invalidJson();
  const parsed = claimSchema.safeParse(body);
  if (!parsed.success) return invalidPayload(parsed.error.issues[0]?.message);

  const { data: entry } = await supabase
    .from("host_event_waitlist")
    .select("id, event_id, user_id")
    .eq("id", parsed.data.waitlistId)
    .eq("user_id", user.id)
    .maybeSingle();
  if (!entry || entry.event_id !== id) {
    return hostEventError("offer_not_found", 404, "No live offer of yours matches that.");
  }

  const { data, error } = await supabase.rpc("host_event_claim_offer", {
    p_user_id: user.id,
    p_waitlist_id: parsed.data.waitlistId,
  });
  if (error) return rpcError(error.message);

  const row = (Array.isArray(data) ? data[0] : data) as HostEventRsvpRow | null;
  if (!row) {
    return hostEventError("claim_failed", 500, "The RSVP didn't come back.", { retryable: true });
  }
  return NextResponse.json({ rsvp: toRsvpDto(row, new Date()) }, { status: 201 });
}
