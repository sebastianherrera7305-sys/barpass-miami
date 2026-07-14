import { NextResponse } from "next/server";
import { createClient as createServiceClient } from "@supabase/supabase-js";
import { z } from "zod";

/**
 * POST /api/passes
 * Registers a Skip the Line / event ticket / table pass server-side right
 * after purchase, so its QR code has a real record to be checked against at
 * the door (see /api/passes/redeem). Without this, a "pass" is just a
 * string in a QR image — anyone could screenshot and reuse it.
 */

const passRequestSchema = z.object({
  passCode: z.string().min(4),
  kind: z.enum(["skip_line", "event_ticket", "table"]),
  venueId: z.string().min(1),
  venueName: z.string().min(1),
  quantity: z.number().int().positive(),
  amount: z.number().nonnegative(),
  validUntil: z.string().datetime(),
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

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }

  const parsed = passRequestSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: "invalid_payload", message: parsed.error.issues[0]?.message },
      { status: 422 },
    );
  }
  const { passCode, kind, venueId, venueName, quantity, amount, validUntil } = parsed.data;

  const { data: pass, error: insertError } = await supabase
    .from("passes")
    .insert({
      pass_code: passCode,
      kind,
      venue_id: venueId,
      venue_name: venueName,
      customer_id: userData.user.id,
      quantity,
      amount,
      valid_until: validUntil,
    })
    .select()
    .single();

  if (insertError) {
    if (insertError.code === "23505") {
      // Duplicate pass_code — client retry after a flaky response, not an error.
      return NextResponse.json({ success: true });
    }
    return NextResponse.json(
      { error: "persist_failed", message: insertError.message },
      { status: 500 },
    );
  }

  return NextResponse.json({ success: true, pass }, { status: 201 });
}
