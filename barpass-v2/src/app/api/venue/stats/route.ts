import { NextResponse } from "next/server";
import { createClient as createServiceClient } from "@supabase/supabase-js";

/**
 * GET /api/venue/stats?venueId=liv-miami
 * Today's numbers for one venue — same shared venue secret as /validate,
 * since this is staff tooling, not a customer-facing endpoint. Reads
 * across orders/passes need the service role because RLS on those tables
 * scopes rows to the customer, not the venue.
 */
export async function GET(request: Request) {
  const secret = request.headers.get("x-venue-secret");
  if (!process.env.VENUE_VALIDATION_SECRET) {
    return NextResponse.json({ error: "validation_not_configured" }, { status: 503 });
  }
  if (!secret || secret !== process.env.VENUE_VALIDATION_SECRET) {
    return NextResponse.json({ error: "not_authorized" }, { status: 401 });
  }

  const venueId = new URL(request.url).searchParams.get("venueId");
  if (!venueId) {
    return NextResponse.json({ error: "missing_venue_id" }, { status: 422 });
  }

  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!supabaseUrl || !serviceRoleKey) {
    return NextResponse.json({ error: "backend_not_configured" }, { status: 503 });
  }
  const supabase = createServiceClient(supabaseUrl, serviceRoleKey);

  const startOfDay = new Date();
  startOfDay.setHours(0, 0, 0, 0);

  const [ordersRes, passesRes] = await Promise.all([
    supabase
      .from("orders")
      .select("id, total, payment_method, status, created_at")
      .eq("vendor_id", venueId)
      .gte("created_at", startOfDay.toISOString())
      .order("created_at", { ascending: false }),
    supabase
      .from("passes")
      .select("id, kind, quantity, amount, redeemed_at, created_at")
      .eq("venue_id", venueId)
      .gte("created_at", startOfDay.toISOString())
      .order("created_at", { ascending: false }),
  ]);

  if (ordersRes.error || passesRes.error) {
    return NextResponse.json(
      { error: "query_failed", message: ordersRes.error?.message ?? passesRes.error?.message },
      { status: 500 },
    );
  }

  const orders = ordersRes.data ?? [];
  const passes = passesRes.data ?? [];

  return NextResponse.json({
    venueId,
    revenueToday: orders.reduce((s, o) => s + Number(o.total), 0) + passes.reduce((s, p) => s + Number(p.amount), 0),
    ordersToday: orders.length,
    passesIssuedToday: passes.length,
    passesRedeemedToday: passes.filter((p) => p.redeemed_at).length,
    recentOrders: orders.slice(0, 20),
    recentPasses: passes.slice(0, 20),
  });
}
