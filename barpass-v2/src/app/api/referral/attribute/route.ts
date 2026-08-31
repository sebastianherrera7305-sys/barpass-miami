import { NextResponse } from "next/server";
import { z } from "zod";
import { checkRateLimit } from "@/lib/rate-limit";
import { requireUser } from "@/lib/supabase/require-user";

/**
 * POST /api/referral/attribute
 * Body: { code }. Attributes the authenticated caller (the referred user) to
 * the referrer who owns `code`. The server derives the referred user id from
 * the token — a client can never claim to be someone else. Attribution is
 * idempotent (unique referred_id) and rejects self-referral server-side.
 * This does NOT grant any points; the reward fires only when the referred
 * user later qualifies (first pass redemption).
 */
const attributeSchema = z.object({
  code: z.string().min(1).max(64),
});

export async function POST(request: Request) {
  const auth = await requireUser(request);
  if (!auth.ok) return auth.response;
  const { supabase, user } = auth;

  const withinLimit = await checkRateLimit(`referral-attribute:${user.id}`, {
    maxRequests: 10,
    windowSeconds: 60,
  });
  if (!withinLimit) {
    return NextResponse.json({ error: "rate_limited" }, { status: 429 });
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }
  const parsed = attributeSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: "invalid_payload" }, { status: 422 });
  }

  const { data: state, error: rpcError } = await supabase.rpc("attribute_referral", {
    p_referred_id: user.id,
    p_code: parsed.data.code,
  });
  if (rpcError) {
    return NextResponse.json({ error: "attribution_failed" }, { status: 500 });
  }
  // RPC returns a status string: 'attributed' | 'invalid_code' | 'self_referral'.
  if (state === "invalid_code") {
    return NextResponse.json({ error: "invalid_code" }, { status: 404 });
  }
  if (state === "self_referral") {
    return NextResponse.json({ error: "self_referral" }, { status: 409 });
  }

  return NextResponse.json({ state });
}
