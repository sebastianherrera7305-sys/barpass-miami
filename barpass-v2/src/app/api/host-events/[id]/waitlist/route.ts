import { NextResponse } from "next/server";
import { z } from "zod";
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
import {
  isOfferClaimable,
  queuePosition,
  type WaitlistEntry,
  type WaitlistState,
} from "@/features/host-events/services/host-event-rules";

/**
 * GET    /api/host-events/[id]/waitlist — the caller's own queue entries,
 *         with their live position and whether an offer is claimable.
 * POST   /api/host-events/[id]/waitlist — join the queue for a sold-out tier.
 * DELETE /api/host-events/[id]/waitlist — leave it.
 *
 * Face value, join-time order, no priority and no way to buy a better place:
 * that is the whole mechanic. When a holder releases a spot it is offered to
 * the head of the queue for `claim_window_minutes`, and if they don't take it
 * the offer moves to the next person — never onto a resale market.
 */

const joinSchema = z.object({ tierId: z.uuid() });

interface WaitlistRow {
  id: string;
  event_id: string;
  tier_id: string;
  user_id: string;
  joined_at: string;
  state: WaitlistState;
  claim_expires_at: string | null;
  offered_at: string | null;
}

function toEntry(row: WaitlistRow): WaitlistEntry {
  return {
    id: row.id,
    userId: row.user_id,
    joinedAt: row.joined_at,
    state: row.state,
    claimExpiresAt: row.claim_expires_at,
  };
}

export async function GET(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const auth = await requireUser(request);
  if (!auth.ok) return auth.response;
  const { supabase, user } = auth;

  // Sweep before reading, so a position is never computed against offers that
  // have already lapsed. Nothing depends on a cron running.
  await supabase.rpc("host_event_sweep_waitlist");

  const { data: mine, error } = await supabase
    .from("host_event_waitlist")
    .select("*")
    .eq("event_id", id)
    .eq("user_id", user.id)
    .in("state", ["waiting", "offered"]);
  if (error) return hostEventError("read_failed", 500, error.message, { retryable: true });

  const rows = (mine ?? []) as WaitlistRow[];
  const now = new Date();

  const entries = await Promise.all(
    rows.map(async (row) => {
      // Positions need the whole tier queue. Only joined_at/state/id are read
      // from other people's rows — never their identity — and the result the
      // caller gets back is a single integer.
      const { data: peers } = await supabase
        .from("host_event_waitlist")
        .select("id, user_id, joined_at, state, claim_expires_at")
        .eq("tier_id", row.tier_id)
        .in("state", ["waiting", "offered"]);
      const queue = ((peers ?? []) as WaitlistRow[]).map(toEntry);
      return {
        id: row.id,
        tierId: row.tier_id,
        state: row.state,
        joinedAt: row.joined_at,
        position: queuePosition(queue, user.id, now),
        offeredAt: row.offered_at,
        claimExpiresAt: row.claim_expires_at,
        claimable: isOfferClaimable(toEntry(row), now),
      };
    }),
  );

  return NextResponse.json({ entries });
}

export async function POST(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const auth = await requireUser(request);
  if (!auth.ok) return auth.response;
  const { supabase, user } = auth;

  const withinLimit = await checkRateLimit(`host-events:waitlist:${user.id}`, {
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
  const parsed = joinSchema.safeParse(body);
  if (!parsed.success) return invalidPayload(parsed.error.issues[0]?.message);

  const { data: tier } = await supabase
    .from("host_event_tiers")
    .select("id")
    .eq("id", parsed.data.tierId)
    .eq("event_id", id)
    .maybeSingle();
  if (!tier) return hostEventError("tier_not_found", 404, "That ticket type doesn't exist.");

  const { data, error } = await supabase.rpc("host_event_join_waitlist", {
    p_user_id: user.id,
    p_tier_id: parsed.data.tierId,
  });
  if (error) return rpcError(error.message);

  const row = (Array.isArray(data) ? data[0] : data) as WaitlistRow | null;
  if (!row) {
    return hostEventError("waitlist_failed", 500, "The queue entry didn't come back.", {
      retryable: true,
    });
  }

  const { data: peers } = await supabase
    .from("host_event_waitlist")
    .select("id, user_id, joined_at, state, claim_expires_at")
    .eq("tier_id", parsed.data.tierId)
    .in("state", ["waiting", "offered"]);
  const now = new Date();

  return NextResponse.json(
    {
      entry: {
        id: row.id,
        tierId: row.tier_id,
        state: row.state,
        joinedAt: row.joined_at,
        position: queuePosition(((peers ?? []) as WaitlistRow[]).map(toEntry), user.id, now),
        claimExpiresAt: row.claim_expires_at,
        claimable: isOfferClaimable(toEntry(row), now),
      },
    },
    { status: 201 },
  );
}

export async function DELETE(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const auth = await requireUser(request);
  if (!auth.ok) return auth.response;
  const { supabase, user } = auth;

  const fromQuery = new URL(request.url).searchParams.get("tierId");
  const source = fromQuery ? { tierId: fromQuery } : await readJson(request);
  if (source === INVALID_JSON) return invalidJson();
  const parsed = joinSchema.safeParse(source);
  if (!parsed.success) return invalidPayload(parsed.error.issues[0]?.message);

  const { data: tier } = await supabase
    .from("host_event_tiers")
    .select("id")
    .eq("id", parsed.data.tierId)
    .eq("event_id", id)
    .maybeSingle();
  if (!tier) return hostEventError("tier_not_found", 404, "That ticket type doesn't exist.");

  const { error } = await supabase.rpc("host_event_leave_waitlist", {
    p_user_id: user.id,
    p_tier_id: parsed.data.tierId,
  });
  if (error) return rpcError(error.message);

  return NextResponse.json({ ok: true });
}
