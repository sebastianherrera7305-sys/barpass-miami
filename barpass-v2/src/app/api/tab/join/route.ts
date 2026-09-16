import { NextResponse } from "next/server";
import { z } from "zod";
import { checkRateLimit } from "@/lib/rate-limit";
import { requireUser } from "@/lib/supabase/require-user";
import { bearerToken, createUserScopedClient } from "@/lib/supabase/user-scoped";
import { mapTabError } from "@/features/tabs/services/tab-errors";

/**
 * POST /api/tab/join — a friend joins the group tab with the six-character
 * code shown on the owner's phone.
 *
 * Rate limited hard and per user: the code space is small by design (it has to
 * be readable across a loud, dark room), so guessing it is the obvious attack.
 * A wrong code is worth nothing on its own — joining a tab lets you add your
 * own charges against your own wallet, never spend someone else's — but it
 * would leak that tab's charges to a stranger, which is enough.
 */

export const joinTabSchema = z.object({ joinCode: z.string().trim().min(1).max(12) });

export async function POST(request: Request) {
  const auth = await requireUser(request);
  if (!auth.ok) return auth.response;

  const withinLimit = await checkRateLimit(`tab-join:${auth.user.id}`, {
    maxRequests: 10,
    windowSeconds: 60,
  });
  if (!withinLimit) return NextResponse.json({ error: "rate_limited" }, { status: 429 });

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }
  const parsed = joinTabSchema.safeParse(body);
  if (!parsed.success) return NextResponse.json({ error: "invalid_payload" }, { status: 422 });

  const token = bearerToken(request);
  if (!token) return NextResponse.json({ error: "not_authenticated" }, { status: 401 });
  const supabase = createUserScopedClient(token);
  if (!supabase) return NextResponse.json({ error: "backend_not_configured" }, { status: 503 });

  const { data, error } = await supabase.rpc("join_venue_tab", {
    p_join_code: parsed.data.joinCode,
  });
  if (error) {
    console.error("[tab/join] join_venue_tab failed", { code: error.code, message: error.message });
    const mapped = mapTabError(error);
    return NextResponse.json({ error: mapped.error }, { status: mapped.status });
  }
  if (!data) return NextResponse.json({ error: "tab_not_found" }, { status: 404 });

  return NextResponse.json({ tabId: data as string });
}
