import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { getSupabaseEnv } from "@/lib/supabase/config";

/**
 * Refreshes the Supabase auth session on navigation so Server Components
 * read a fresh session cookie.
 *
 * There are no auth-gated routes at launch, so this middleware NEVER blocks
 * or redirects — it only keeps the session cookie warm when Supabase is
 * configured. When it isn't, it no-ops instead of crashing the request
 * (an unconfigured client here previously 500'd every route on the site).
 */
export async function middleware(request: NextRequest) {
  const env = getSupabaseEnv();
  if (!env) return NextResponse.next({ request });

  let response = NextResponse.next({ request });

  const supabase = createServerClient(env.url, env.anonKey, {
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(cookiesToSet) {
        cookiesToSet.forEach(({ name, value }) =>
          request.cookies.set(name, value),
        );
        response = NextResponse.next({ request });
        cookiesToSet.forEach(({ name, value, options }) =>
          response.cookies.set(name, value, options),
        );
      },
    },
  });

  // Touch the session so @supabase/ssr can rotate the cookie if needed.
  // We intentionally do not gate any route on the result.
  await supabase.auth.getUser();

  return response;
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
};
