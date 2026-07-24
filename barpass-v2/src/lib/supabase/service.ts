import { createClient as createServiceClient, type SupabaseClient } from "@supabase/supabase-js";

/**
 * Service-role Supabase client factory — bypasses RLS.
 *
 * Every privileged API route (wallet, transactions, passes, account
 * deletion) has independently constructed this same client inline. This is
 * the first caller outside `api/` (a public Server Component, not a route
 * handler), so it's extracted here rather than duplicated a further time.
 * Existing routes are untouched — consolidating them is a separate,
 * unapproved change, not part of this task.
 *
 * SECURITY: this client bypasses every RLS policy in the database. Never
 * import it into client-side code, and never forward its raw query results
 * to a client — always narrow to an explicit DTO first (see
 * trip-preview-service.ts for the pattern).
 */
export function createServiceRoleClient(): SupabaseClient | null {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !serviceRoleKey) return null;
  return createServiceClient(url, serviceRoleKey);
}
