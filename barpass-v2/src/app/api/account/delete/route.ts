import { NextResponse } from "next/server";
import { createClient as createServiceClient } from "@supabase/supabase-js";
import { checkRateLimit } from "@/lib/rate-limit";

/**
 * POST /api/account/delete
 * Deletes the authenticated user's account (Apple Guideline 5.1.1(v)).
 *
 * Auth model mirrors every other privileged route: the client sends its own
 * Bearer access token, the server validates it with auth.getUser() and only
 * ever deletes THAT user — the client never names a user id, so one account
 * can never delete another. All privileged work uses the service-role key
 * server-side; admin.deleteUser is never exposed to the client.
 *
 * Deletion strategy (approved):
 *   - trips the user created            → deleted (creator_id CASCADE)
 *   - profile / preferences / favorites → deleted (CASCADE)
 *   - wallet balance + wallet ledger    → deleted (CASCADE) with the user
 *   - orders / passes / venue_posts     → KEPT, customer_id/user_id SET NULL
 *                                          (financial + venue audit trail
 *                                          preserved, anonymized)
 *   - stale membership in OTHER users'  → stripped via remove_user_from_all_trips
 *     trips (uuid[] arrays, no FK)
 * The wallet balance is intentionally forfeited on delete; the iOS flow warns
 * the user of any nonzero balance and requires explicit confirmation first.
 */
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
  const userId = userData.user.id;

  // A user can only ever delete their own account, so a low cap is plenty
  // and blocks a token being hammered against this endpoint.
  const withinLimit = await checkRateLimit(`account-delete:${userId}`, {
    maxRequests: 5,
    windowSeconds: 60,
  });
  if (!withinLimit) {
    return NextResponse.json({ error: "rate_limited" }, { status: 429 });
  }

  // 1) Strip the user from other people's trip arrays (no FK cascade covers these).
  const { error: tripsError } = await supabase.rpc("remove_user_from_all_trips", {
    p_user_id: userId,
  });
  if (tripsError) {
    return NextResponse.json({ error: "deletion_failed", stage: "trips" }, { status: 500 });
  }

  // 2) Delete the auth user. FK CASCADE / SET NULL handle every other table.
  const { error: deleteError } = await supabase.auth.admin.deleteUser(userId);
  if (deleteError) {
    return NextResponse.json({ error: "deletion_failed", stage: "auth" }, { status: 500 });
  }

  return NextResponse.json({ success: true });
}
