import { createBrowserClient } from "@supabase/ssr";

/**
 * Browser-side Supabase client.
 * Used inside Client Components and hooks. Auth session is shared with the
 * server client via cookies (@supabase/ssr handles the sync).
 */
export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  );
}
