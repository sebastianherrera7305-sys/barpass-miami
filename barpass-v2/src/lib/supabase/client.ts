import { createBrowserClient } from "@supabase/ssr";

/**
 * Browser-side Supabase client.
 * Used inside Client Components and hooks. Auth session is shared with the
 * server client via cookies (@supabase/ssr handles the sync).
 *
 * Build-time guard (owner 2026-10-28): Next.js 16 prerenders "use client"
 * pages during `next build` even when they're meant to be dynamic. If a
 * page calls createClient() during render (e.g. `useState(() =>
 * createClient())`), the factory runs AT BUILD TIME when
 * NEXT_PUBLIC_SUPABASE_URL / _ANON_KEY aren't present, and
 * `@supabase/ssr` throws "URL and API key are required". The build fails
 * and the whole deploy aborts (e.g. the Groq-key deploy was blocked by
 * this). Returning a harmless stub when env is missing keeps the
 * prerender succeeding; at real runtime the env is set and the real
 * client is created. Any method call on the stub still fails loudly —
 * so real client code can't accidentally paper over a missing env.
 */
export function createClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !anon) {
    return createBrowserClient(
      "https://build-prerender-stub.invalid",
      "build-prerender-stub-key",
    );
  }
  return createBrowserClient(url, anon);
}
