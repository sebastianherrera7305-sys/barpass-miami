import { NextResponse } from "next/server";
import { createClient as createServiceClient } from "@supabase/supabase-js";
import { z } from "zod";
import { checkRateLimit } from "@/lib/rate-limit";

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
  const authHeader = request.headers.get("authorization");
  const token = authHeader?.startsWith("Bearer ") ? authHeader.slice(7) : null;
  if (!token) {
    return NextResponse.json({ error: "not_authenticated" }, { status: 401 });
  }

  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!supabaseUrl || !serviceRoleKey) {
    return NextResponse.json({ error: "backend_not_configured" }, { status: 503 });
  }

  const supabase = createServiceClient(supabaseUrl, serviceRoleKey);
  const { data: userData, error: userError } = await supabase.auth.getUser(token);
  if (userError || !userData?.user) {
    return NextResponse.json({ error: "not_authenticated" }, { status: 401 });
  }

  const withinLimit = await checkRateLimit(`referral-attribute:${userData.user.id}`, {
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
    p_referred_id: userData.user.id,
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
