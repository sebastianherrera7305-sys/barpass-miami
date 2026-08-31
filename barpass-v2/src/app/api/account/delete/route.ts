import { NextResponse } from "next/server";
import { checkRateLimit } from "@/lib/rate-limit";
import { requireUser } from "@/lib/supabase/require-user";

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
 *   - stale membership in OTHER users'  → stripped inline with the service-
 *     trips (uuid[] arrays, no FK)         role client (no manual migration)
 * The wallet balance is intentionally forfeited on delete; the iOS flow warns
 * the user of any nonzero balance and requires explicit confirmation first.
 */
export async function POST(request: Request) {
  const auth = await requireUser(request);
  if (!auth.ok) return auth.response;
  const { supabase, user } = auth;
  const userId = user.id;

  // A user can only ever delete their own account, so a low cap is plenty
  // and blocks a token being hammered against this endpoint.
  const withinLimit = await checkRateLimit(`account-delete:${userId}`, {
    maxRequests: 5,
    windowSeconds: 60,
  });
  if (!withinLimit) {
    return NextResponse.json({ error: "rate_limited" }, { status: 429 });
  }

  // 1) Strip the user from other people's trip arrays. These are plain
  //    uuid[] columns with no FK, so nothing cascades them. Done inline with
  //    the service-role client (which bypasses RLS) rather than via a
  //    SECURITY DEFINER RPC, so account deletion needs zero manual DB
  //    migration to work. Deletion is rare and scoped to one user's own
  //    memberships, so a select-then-update is fine — no atomicity concern.
  const { data: memberTrips, error: fetchError } = await supabase
    .from("trips")
    .select("id, member_ids, co_organizer_ids, pending_requests")
    .or(
      `member_ids.cs.{${userId}},co_organizer_ids.cs.{${userId}},pending_requests.cs.{${userId}}`,
    );
  if (fetchError) {
    return NextResponse.json({ error: "deletion_failed", stage: "trips" }, { status: 500 });
  }
  for (const trip of memberTrips ?? []) {
    const strip = (arr: string[] | null) => (arr ?? []).filter((id) => id !== userId);
    const { error: updateError } = await supabase
      .from("trips")
      .update({
        member_ids: strip(trip.member_ids),
        co_organizer_ids: strip(trip.co_organizer_ids),
        pending_requests: strip(trip.pending_requests),
      })
      .eq("id", trip.id);
    if (updateError) {
      return NextResponse.json({ error: "deletion_failed", stage: "trips" }, { status: 500 });
    }
  }

  // 2) Delete the auth user. FK CASCADE / SET NULL handle every other table.
  const { error: deleteError } = await supabase.auth.admin.deleteUser(userId);
  if (deleteError) {
    return NextResponse.json({ error: "deletion_failed", stage: "auth" }, { status: 500 });
  }

  return NextResponse.json({ success: true });
}
