import { NextResponse } from "next/server";
import { createClient as createServiceClient } from "@supabase/supabase-js";
import { z } from "zod";
import { checkRateLimit } from "@/lib/rate-limit";
import { venueSecretMatches } from "@/lib/venue-secret";

/**
 * POST /api/passes/redeem
 * Door-staff validation. Requires that venue's own secret, read from the
 * locked-down `venue_secrets` table (supabase/venue_secrets_lockdown.sql —
 * previously stored on the publicly-readable `venues` table and exposed to
 * any anon client) rather than a customer Supabase session — the person
 * scanning is staff, not the pass holder. Redemption is atomic: a pass can
 * only ever be marked used once.
 */

const redeemRequestSchema = z.object({
  passCode: z.string().min(1),
  venueId: z.string().min(1),
});

export async function POST(request: Request) {
  const secret = request.headers.get("x-venue-secret");
  if (!secret) {
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
  const { venueId } = parsed.data;

  // 30 canjes/minuto por venue — cubre una fila de puerta activa sin abrir
  // la puerta a fuerza bruta del secreto o del pass_code.
  const withinLimit = await checkRateLimit(`passes-redeem:${venueId}`, {
    maxRequests: 30,
    windowSeconds: 60,
  });
  if (!withinLimit) {
    return NextResponse.json({ error: "rate_limited" }, { status: 429 });
  }

  const { data: venueSecret, error: venueError } = await supabase
    .from("venue_secrets")
    .select("validation_secret")
    .eq("venue_id", venueId)
    .maybeSingle();
  if (venueError || !venueSecret?.validation_secret) {
    return NextResponse.json({ error: "venue_not_found" }, { status: 404 });
  }
  if (!venueSecretMatches(secret, venueSecret.validation_secret)) {
    return NextResponse.json({ error: "not_authorized" }, { status: 401 });
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
  // El secreto de un venue solo puede canjear pases DE ese venue — sin esto,
  // cualquier staff podría canjear un pase de otro local con su propio secreto.
  if (pass.venue_id !== venueId) {
    return NextResponse.json({ error: "wrong_venue" }, { status: 403 });
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

  // Referral qualification (S4): a redeemed pass is the referred user's first
  // real venue presence. The RPC is idempotent and only acts on a still-
  // 'attributed' referral, so this is safe to call on every redemption. It
  // must never affect the redemption result — a referral failure is logged
  // and swallowed (same fail-open stance as rate limiting).
  if (updated.customer_id) {
    const { error: referralError } = await supabase.rpc("qualify_and_reward_referral", {
      p_referred_id: updated.customer_id,
    });
    if (referralError) {
      console.error("[redeem] referral qualification failed (non-fatal)", {
        customerId: updated.customer_id,
        code: referralError.code,
        message: referralError.message,
      });
    }
  }

  return NextResponse.json({ success: true, pass: updated });
}
