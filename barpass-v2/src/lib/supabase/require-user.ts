import { NextResponse } from "next/server";
import { createClient as createServiceClient, type SupabaseClient, type User } from "@supabase/supabase-js";

type RequireUserResult =
  | { ok: true; supabase: SupabaseClient; user: User }
  | { ok: false; response: NextResponse };

/**
 * Shared auth check for API routes that take a client Bearer token and act
 * with the service-role key (passes, referral, transactions, wallet,
 * account/delete). Not for routes using the cookie-bound session client
 * (@/lib/supabase/server) — those get their user from RLS, not this.
 */
export async function requireUser(request: Request): Promise<RequireUserResult> {
  const authHeader = request.headers.get("authorization");
  const token = authHeader?.startsWith("Bearer ") ? authHeader.slice(7) : null;
  if (!token) {
    return { ok: false, response: NextResponse.json({ error: "not_authenticated" }, { status: 401 }) };
  }

  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!supabaseUrl || !serviceRoleKey) {
    return { ok: false, response: NextResponse.json({ error: "backend_not_configured" }, { status: 503 }) };
  }

  const supabase = createServiceClient(supabaseUrl, serviceRoleKey);
  const { data: userData, error: userError } = await supabase.auth.getUser(token);
  if (userError || !userData?.user) {
    return { ok: false, response: NextResponse.json({ error: "not_authenticated" }, { status: 401 }) };
  }

  return { ok: true, supabase, user: userData.user };
}
