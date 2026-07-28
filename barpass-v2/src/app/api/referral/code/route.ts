import { NextResponse } from "next/server";
import { createClient as createServiceClient } from "@supabase/supabase-js";
import { checkRateLimit } from "@/lib/rate-limit";

/**
 * GET /api/referral/code
 * Returns the authenticated caller's own referral code, generating it once
 * on first request. The code is server-generated (never client-chosen) and
 * lives in the policy-less referral_codes table — this route, using the
 * service role, is the only read path. Feeds ShareManager.shareReferral.
 */
export async function GET(request: Request) {
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

  const withinLimit = await checkRateLimit(`referral-code:${userData.user.id}`, {
    maxRequests: 20,
    windowSeconds: 60,
  });
  if (!withinLimit) {
    return NextResponse.json({ error: "rate_limited" }, { status: 429 });
  }

  const { data: code, error: rpcError } = await supabase.rpc("get_or_create_referral_code", {
    p_user_id: userData.user.id,
  });
  if (rpcError || !code) {
    return NextResponse.json({ error: "code_unavailable" }, { status: 500 });
  }

  return NextResponse.json({ code });
}
