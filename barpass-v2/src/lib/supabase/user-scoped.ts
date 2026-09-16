import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { getSupabaseEnv } from "./config";

/**
 * A Supabase client that acts AS the caller, not as the service role.
 *
 * `requireUser` hands back a service-role client, which is what the wallet and
 * pass routes want. The venue-tab RPCs cannot use it: `open_venue_tab`,
 * `join_venue_tab`, `issue_tab_scan_token` and `close_venue_tab` all resolve
 * the caller with `auth.uid()`, which is NULL under the service role — every
 * call would raise `not_authenticated`. The same applies to reading a tab:
 * the whole point of GET /api/tab is that RLS decides what this person may
 * see, and the service role bypasses RLS entirely.
 *
 * So: the Bearer token is verified once by `requireUser` (real user, real
 * session), and the actual work goes through this anon-key client carrying
 * that same token.
 */
export function createUserScopedClient(accessToken: string): SupabaseClient | null {
  const env = getSupabaseEnv();
  if (!env) return null;
  return createClient(env.url, env.anonKey, {
    global: { headers: { Authorization: `Bearer ${accessToken}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/** The raw Bearer token of the request, or null. Mirrors `requireUser`'s parse. */
export function bearerToken(request: Request): string | null {
  const header = request.headers.get("authorization");
  return header?.startsWith("Bearer ") ? header.slice(7) : null;
}
