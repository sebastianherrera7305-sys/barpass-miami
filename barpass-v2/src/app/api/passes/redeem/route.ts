import { NextResponse } from "next/server";
import { createClient as createServiceClient } from "@supabase/supabase-js";
import { z } from "zod";

/**
 * POST /api/passes/redeem
 * Door-staff validation. Requires the shared venue secret (set once on the
 * /validate page, stored in venue staff's browser) rather than a customer
 * Supabase session — the person scanning is staff, not the pass holder.
 * Redemption is atomic: a pass can only ever be marked used once.
 */

const redeemRequestSchema = z.object({
  passCode: z.string().min(1),
});

export async function POST(request: Request) {
  const secret = request.headers.get("x-venue-secret");
  if (!process.env.VENUE_VALIDATION_SECRET) {
    return NextResponse.json({ error: "validation_not_configured" }, { status: 503 });
  }
  if (!secret || secret !== process.env.VENUE_VALIDATION_SECRET) {
    return NextResponse.json({ error: "not_authorized" }, { status: 401 });
  }

  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!supabaseUrl || !serviceRoleKey) {
    return NextResponse.json({ error: "backend_not_configured" }, { status: 503 });
  }
  const supabase = createServiceClient(supabaseUrl, serviceRoleKey);

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }
  const parsed = redeemRequestSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: "invalid_payload" }, { status: 422 });
  }

  const { data: pass, error: lookupError } = await supabase
    .from("passes")
    .select("*")
    .eq("pass_code", parsed.data.passCode.trim().toUpperCase())
    .maybeSingle();

  if (lookupError) {
    return NextResponse.json({ error: "lookup_failed", message: lookupError.message }, { status: 500 });
  }
  if (!pass) {
    return NextResponse.json({ error: "not_found" }, { status: 404 });
  }
  if (pass.redeemed_at) {
    return NextResponse.json(
      { error: "already_redeemed", redeemedAt: pass.redeemed_at, pass },
      { status: 409 },
    );
  }
  if (new Date(pass.valid_until) < new Date()) {
    return NextResponse.json({ error: "expired", pass }, { status: 410 });
  }

  const { data: updated, error: updateError } = await supabase
    .from("passes")
    .update({ redeemed_at: new Date().toISOString(), redeemed_by: "venue" })
    .eq("id", pass.id)
    .eq("pass_code", pass.pass_code)
    .is("redeemed_at", null) // race guard — two simultaneous scans can't both win
    .select()
    .single();

  if (updateError || !updated) {
    return NextResponse.json({ error: "already_redeemed" }, { status: 409 });
  }

  return NextResponse.json({ success: true, pass: updated });
}
