import { NextResponse } from "next/server";
import { z } from "zod";
import { checkRateLimit } from "@/lib/rate-limit";
import { requireUser } from "@/lib/supabase/require-user";
import { bearerToken, createUserScopedClient } from "@/lib/supabase/user-scoped";
import { mapTabError } from "@/features/tabs/services/tab-errors";

/**
 * POST /api/tab/scan-token — the phone asks for the code it is about to turn
 * into a QR at the bar.
 *
 * `maxAmount` is the ceiling the person approves for this one scan, and the
 * upper bound of 1000 mirrors the CHECK on venue_tab_scan_tokens: a value the
 * database would reject should be a 422 here, not a 500 from Postgres.
 * Issuing a new token silently kills this user's previous ones on the tab
 * (§ 7), so the client should treat the response as the only live code.
 */

export const scanTokenSchema = z.object({
  tabId: z.uuid(),
  maxAmount: z.number().positive().max(1000),
});

type ScanTokenRow = { token: string; expires_at: string };

export async function POST(request: Request) {
  const auth = await requireUser(request);
  if (!auth.ok) return auth.response;

  // 30/minuto: mostrar el código, guardarlo, volver a abrirlo y regenerarlo
  // es normal en una barra; un loop que mina tokens no lo es.
  const withinLimit = await checkRateLimit(`tab-scan-token:${auth.user.id}`, {
    maxRequests: 30,
    windowSeconds: 60,
  });
  if (!withinLimit) return NextResponse.json({ error: "rate_limited" }, { status: 429 });

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }
  const parsed = scanTokenSchema.safeParse(body);
  if (!parsed.success) return NextResponse.json({ error: "invalid_payload" }, { status: 422 });

  const token = bearerToken(request);
  if (!token) return NextResponse.json({ error: "not_authenticated" }, { status: 401 });
  const supabase = createUserScopedClient(token);
  if (!supabase) return NextResponse.json({ error: "backend_not_configured" }, { status: 503 });

  const { data, error } = await supabase.rpc("issue_tab_scan_token", {
    p_tab_id: parsed.data.tabId,
    p_max_amount: parsed.data.maxAmount,
  });
  if (error) {
    console.error("[tab/scan-token] issue_tab_scan_token failed", {
      code: error.code,
      message: error.message,
    });
    const mapped = mapTabError(error);
    return NextResponse.json({ error: mapped.error }, { status: mapped.status });
  }
  const row = (data as ScanTokenRow[] | null)?.[0];
  if (!row) return NextResponse.json({ error: "tab_operation_failed" }, { status: 500 });

  return NextResponse.json({ token: row.token, expiresAt: row.expires_at });
}
