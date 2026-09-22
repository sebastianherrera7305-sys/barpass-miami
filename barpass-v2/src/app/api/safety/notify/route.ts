import { NextResponse } from "next/server";
import { z } from "zod";
import { apnsConfig, sendPush, type SendResult } from "@/lib/apns";
import { checkRateLimit } from "@/lib/rate-limit";
import {
  buildRefreshPayload,
  buildSeekLeaderPayload,
  cleanName,
  type ApnsEnvironment,
  type PushTarget,
} from "@/lib/safety-push-rules";
import { requireUser } from "@/lib/supabase/require-user";

/**
 * POST /api/safety/notify — fans a safety-group event out over APNs.
 *
 *   { type: "seek_leader", seekId }  → time-sensitive alert to the group
 *                                       LEADER and nobody else (state B of the
 *                                       radar → handshake → rally point machine).
 *   { type: "refresh",     groupId } → silent content-available push.
 *
 * The client never sends a token or a recipient list. It names a seek (or a
 * group) it belongs to, and the recipients come from a service-role-only RPC
 * that re-checks, in SQL, that the caller is the seeker of that seek and that
 * nobody blocked anybody (safety_groups.sql §6). A stolen session therefore
 * can only ever notify the leader of a group it is actually in.
 *
 * Nothing here is required for a search to work: the seek row is saved by
 * seek_group_leader() before this is ever called, so a 503 for a missing APNs
 * key only means "the leader sees it when they open the app".
 *
 * No coordinates, distance or direction cross this route in either direction.
 */

export const runtime = "nodejs";

export const notifyRequestSchema = z.discriminatedUnion("type", [
  z.object({ type: z.literal("seek_leader"), seekId: z.string().uuid() }),
  z.object({ type: z.literal("refresh"), groupId: z.string().uuid() }),
]);

interface SeekTargetRow {
  token: string;
  environment: ApnsEnvironment;
  seeker_name: string | null;
  expires_at: string;
  group_id: string;
}
interface RefreshTargetRow {
  token: string;
  environment: ApnsEnvironment;
}

export async function POST(request: Request) {
  const auth = await requireUser(request);
  if (!auth.ok) return auth.response;
  const { supabase, user } = auth;

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }
  const parsed = notifyRequestSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: "invalid_payload" }, { status: 422 });
  }
  const input = parsed.data;

  // Refresh pings are cheap and frequent (chat); a seek interrupts the
  // leader's phone in a way that breaks through Focus, so it gets the tighter
  // cap (the RPC also limits seeks to 6/hour per person).
  const withinLimit = await checkRateLimit(`safety-notify:${input.type}:${user.id}`, {
    maxRequests: input.type === "seek_leader" ? 6 : 30,
    windowSeconds: input.type === "seek_leader" ? 3600 : 60,
  });
  if (!withinLimit) {
    return NextResponse.json({ error: "rate_limited" }, { status: 429 });
  }

  const config = apnsConfig();
  if (!config) {
    return NextResponse.json({ error: "push_not_configured" }, { status: 503 });
  }

  let targets: PushTarget[];
  let results: SendResult[];

  if (input.type === "seek_leader") {
    const { data, error } = await supabase.rpc("get_seek_push_targets", {
      p_seek_id: input.seekId,
      p_sender: user.id,
    });
    if (error) {
      console.error("[safety/notify] targets rpc failed", { code: error.code });
      return NextResponse.json({ error: "targets_failed" }, { status: 500 });
    }
    const rows = (data ?? []) as SeekTargetRow[];
    if (rows.length === 0) {
      // Not the seeker, seek gone/expired/ended, leader changed, or the leader
      // has no registered phone. Indistinguishable on purpose: this route must
      // not reveal whether a group or seek exists to someone who is not in it.
      return NextResponse.json({ sent: 0, failed: 0, recipients: 0 });
    }
    targets = rows.map((r) => ({ token: r.token, environment: r.environment }));
    const payload = buildSeekLeaderPayload({
      seekId: input.seekId,
      groupId: rows[0].group_id,
      seekerName: cleanName(rows[0].seeker_name),
      expiresAt: rows[0].expires_at,
    });
    results = await sendPush(config, targets, {
      kind: "alert",
      payload,
      expiresAtUnix: Math.floor(new Date(rows[0].expires_at).getTime() / 1000),
    });
  } else {
    const { data, error } = await supabase.rpc("get_group_refresh_push_targets", {
      p_group_id: input.groupId,
      p_sender: user.id,
    });
    if (error) {
      console.error("[safety/notify] refresh targets rpc failed", { code: error.code });
      return NextResponse.json({ error: "targets_failed" }, { status: 500 });
    }
    const rows = (data ?? []) as RefreshTargetRow[];
    if (rows.length === 0) return NextResponse.json({ sent: 0, failed: 0, recipients: 0 });
    targets = rows.map((r) => ({ token: r.token, environment: r.environment }));
    results = await sendPush(config, targets, {
      kind: "background",
      payload: buildRefreshPayload(input.groupId),
      // A "refresh" that arrives ten minutes late is worthless — do not
      // let APNs store it.
      expiresAtUnix: 0,
    });
  }

  const dead = results.filter((r) => r.dead).map((r) => r.token);
  if (dead.length > 0) {
    await supabase.rpc("delete_dead_device_tokens", { p_tokens: dead });
  }

  return NextResponse.json({
    recipients: targets.length,
    sent: results.filter((r) => r.ok).length,
    failed: results.filter((r) => !r.ok).length,
  });
}
