import { NextResponse } from "next/server";
import { createClient as createServiceClient } from "@supabase/supabase-js";
import { z } from "zod";
import { checkRateLimit } from "@/lib/rate-limit";
import { venueSecretMatches } from "@/lib/venue-secret";
import { mapChargeError } from "@/features/tabs/services/tab-errors";

/**
 * POST /api/venue/tab/charge — the bar side of "la cuenta".
 *
 * Two independent facts have to hold before a cent moves, and this route is
 * the only place they meet (supabase/venue_tabs.sql, header):
 *   1. `x-venue-secret` proves WHICH VENUE is asking — compared in constant
 *      time against `venue_secrets`, exactly as /api/passes/redeem does.
 *   2. `token` proves THIS PERSON approved THIS CHARGE — single use, three
 *      minutes, and capped at an amount they chose.
 * The venue never sends a user id, and never receives one back: the response
 * carries the charge id and the amount, nothing that names or profiles the
 * customer (their wallet balance least of all).
 *
 * `charge_venue_tab` is revoked from anon AND authenticated on purpose, so it
 * runs here under the service role or it does not run at all.
 */

export const chargeRequestSchema = z.object({
  token: z.string().min(1),
  venueId: z.uuid(),
  // 1000 is the CHECK on venue_tab_charges.amount; rejecting it here keeps a
  // fat-fingered POS entry a 422 instead of a Postgres constraint error.
  amount: z.number().positive().max(1000),
  description: z.string().trim().min(1).max(200),
  // Stored verbatim as the receipt line (jsonb): the menu may change later,
  // the receipt may not. Optional — the RPC defaults it to [].
  items: z.array(z.unknown()).optional(),
  idempotencyKey: z.string().min(1).max(200),
});

type ChargeRow = { charge_id: string; amount: number };

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
  const parsed = chargeRequestSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: "invalid_payload" }, { status: 422 });
  }
  const { token, venueId, amount, description, items, idempotencyKey } = parsed.data;

  // 120 cobros/minuto por venue: una barra llena con varios bartenders cobra
  // seguido, y este límite no debe ser el que corta la noche. Sigue siendo un
  // techo contra fuerza bruta del secreto o de los tokens, que son hex de 24
  // bytes — a 120/min no se adivinan.
  const withinLimit = await checkRateLimit(`venue-tab-charge:${venueId}`, {
    maxRequests: 120,
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

  const { data, error } = await supabase.rpc("charge_venue_tab", {
    p_token: token,
    p_venue_id: venueId,
    p_amount: amount,
    p_description: description,
    p_items: items ?? [],
    p_idempotency_key: idempotencyKey,
  });

  if (error) {
    // Logged in full for us, mapped to a bare code for the tablet.
    console.error("[venue/tab/charge] charge_venue_tab failed", {
      venueId,
      idempotencyKey,
      code: error.code,
      message: error.message,
    });
    const mapped = mapChargeError(error);
    return NextResponse.json({ error: mapped.error }, { status: mapped.status });
  }

  const row = (data as ChargeRow[] | null)?.[0];
  if (!row) {
    console.error("[venue/tab/charge] charge_venue_tab returned no row", { venueId, idempotencyKey });
    return NextResponse.json({ error: "charge_failed" }, { status: 500 });
  }

  // Deliberately NOT returned: member_id and remaining_balance. The RPC hands
  // them back because the customer's phone will want them; the bar must not
  // learn who paid or how much money they have left.
  return NextResponse.json({ success: true, chargeId: row.charge_id, amount: row.amount });
}
