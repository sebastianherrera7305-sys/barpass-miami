import "server-only";
import {
  createClient as createServiceClient,
  type SupabaseClient,
  type User,
} from "@supabase/supabase-js";
import type { ModerationError } from "./types";

/**
 * Who is allowed to look at reported photos.
 *
 * This is NOT `requireUser` (src/lib/supabase/require-user.ts): that helper
 * is Request-shaped and answers with a NextResponse, and Server Actions
 * have neither a Request nor a response to return. The auth check itself is
 * deliberately the same one — Bearer token in, service-role client +
 * `auth.getUser(token)` out — so there is one way to verify a caller in
 * this codebase, not two.
 *
 * WHAT THE PROJECT ACTUALLY HAS TODAY, said plainly: there is no admin role
 * in the database. `venue_owners` is provisioned by hand for bar staff and
 * `VENUE_VALIDATION_SECRET` is a shared PIN for the door — neither is a
 * staff identity. So the gate here is an env allowlist of BarPass emails,
 * which is the same shape of control the door page already uses, and its
 * weaknesses are written down in the handoff rather than hidden: it is a
 * redeploy to change, it inherits whatever password hygiene the account
 * has, and it is not a substitute for a real `app_moderators` table once
 * more than one person does this job.
 */

export type ModeratorGate =
  | { ok: true; supabase: SupabaseClient; user: User }
  | { ok: false; error: ModerationError };

/** Comma-separated, case-insensitive. Empty means nobody — never everybody. */
function moderatorEmails(): string[] {
  return (process.env.BARPASS_MODERATOR_EMAILS ?? "")
    .split(",")
    .map((email) => email.trim().toLowerCase())
    .filter(Boolean);
}

export async function requireModerator(accessToken: string | null): Promise<ModeratorGate> {
  const allowed = moderatorEmails();
  // Fail closed. An unset env var must lock the page, not open it: the one
  // failure mode that cannot be allowed here is a stranger paging through
  // other people's photos because a deploy forgot a variable.
  if (allowed.length === 0) return { ok: false, error: "moderation_not_configured" };

  if (!accessToken) return { ok: false, error: "not_authenticated" };

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !serviceRoleKey) return { ok: false, error: "backend_not_configured" };

  const supabase = createServiceClient(url, serviceRoleKey);
  const { data, error } = await supabase.auth.getUser(accessToken);
  if (error || !data?.user) return { ok: false, error: "not_authenticated" };

  const user = data.user;
  const email = user.email?.trim().toLowerCase();
  // email_confirmed_at matters: if this project ever turns off email
  // confirmation, an allowlisted address would otherwise be claimable by
  // anyone who can type it into the signup form.
  if (!email || !user.email_confirmed_at) return { ok: false, error: "not_a_moderator" };
  if (!allowed.includes(email)) return { ok: false, error: "not_a_moderator" };

  return { ok: true, supabase, user };
}
