import { NextResponse } from "next/server";
import { checkRateLimit } from "@/lib/rate-limit";
import { requireUser } from "@/lib/supabase/require-user";

/**
 * GET /api/referral/code
 * Returns the authenticated caller's own referral code, generating it once
 * on first request. The code is server-generated (never client-chosen) and
 * lives in the policy-less referral_codes table — this route, using the
 * service role, is the only read path. Feeds ShareManager.shareReferral.
 */
export async function GET(request: Request) {
  const auth = await requireUser(request);
  if (!auth.ok) return auth.response;
  const { supabase, user } = auth;

  const withinLimit = await checkRateLimit(`referral-code:${user.id}`, {
    maxRequests: 20,
    windowSeconds: 60,
  });
  if (!withinLimit) {
    return NextResponse.json({ error: "rate_limited" }, { status: 429 });
  }

  const { data: code, error: rpcError } = await supabase.rpc("get_or_create_referral_code", {
    p_user_id: user.id,
  });
  if (rpcError || !code) {
    return NextResponse.json({ error: "code_unavailable" }, { status: 500 });
  }

  return NextResponse.json({ code });
}
