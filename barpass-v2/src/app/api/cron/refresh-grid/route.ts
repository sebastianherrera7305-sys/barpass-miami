import { NextResponse } from "next/server";
import { createClient as createServiceClient } from "@supabase/supabase-js";

/**
 * GET /api/cron/refresh-grid
 * Recomputes grid_pulses (The Grid's public, aggregated presence-per-venue
 * table) from raw venue_checkins. Meant to be hit every 5 min by Vercel
 * Cron — see vercel.json. Requires CRON_SECRET so this can't be triggered
 * by anyone who finds the URL (it only calls a SECURITY DEFINER RPC, no
 * user data is readable through this route either way, but rate-limiting
 * who can force a recompute is still worth doing).
 */
export async function GET(request: Request) {
  const authHeader = request.headers.get("authorization");
  if (authHeader !== `Bearer ${process.env.CRON_SECRET}`) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!supabaseUrl || !serviceRoleKey) {
    return NextResponse.json({ error: "not configured" }, { status: 503 });
  }

  const supabase = createServiceClient(supabaseUrl, serviceRoleKey);
  const { error } = await supabase.rpc("refresh_grid_pulses");
  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json({ ok: true });
}
