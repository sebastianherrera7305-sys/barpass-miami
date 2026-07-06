/**
 * Supabase configuration guard.
 *
 * The app is discovery-first: nothing at launch requires a logged-in user,
 * and venue data comes from the local catalog (see features/venues). Supabase
 * is scaffolded for when auth, favorites, and realtime land — but its absence
 * must NEVER take the site down. Every Supabase entry point checks this first.
 */
export function isSupabaseConfigured(): boolean {
  return (
    !!process.env.NEXT_PUBLIC_SUPABASE_URL &&
    !!process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
  );
}

/** Returns the Supabase URL + anon key, or null when unconfigured. */
export function getSupabaseEnv(): { url: string; anonKey: string } | null {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !anonKey) return null;
  return { url, anonKey };
}
