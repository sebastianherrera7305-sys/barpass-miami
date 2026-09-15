import { NextResponse } from "next/server";
import { requireUser } from "@/lib/supabase/require-user";
import { ownerError } from "@/features/venue-owner/services/owner-errors";

/**
 * GET /api/venue-owner/venues — the venues this user speaks for.
 *
 * `venue_owners` is provisioned by ops with the service role and has no
 * self-serve claim path by design (supabase/venue_owner_events_promos.sql,
 * supabase/grant_venue_owner.sql). An empty list here is the normal answer
 * for an account nobody has granted anything to — it is not an error.
 *
 * Same auth wrapper as the other service-role routes: a Bearer token from the
 * caller's Supabase session. `venue_owners` is readable under RLS too, but the
 * rest of this route family (orders, passes) is not, so identity and data come
 * from one consistent place.
 */
export async function GET(request: Request) {
  const auth = await requireUser(request);
  if (!auth.ok) return auth.response;
  const { supabase, user } = auth;

  const { data, error } = await supabase
    .from("venue_owners")
    .select("venue_id, role, venues(id, name, slug, city, excluded_reason, business_status)")
    .eq("user_id", user.id);

  if (error) {
    return ownerError("owner_lookup_failed", 503, error.message, { retryable: true });
  }

  type Row = {
    venue_id: string;
    role: string | null;
    venues: { id: string; name: string; slug: string; city: string | null; excluded_reason: string | null; business_status: string | null } | null;
  };

  const venues = ((data ?? []) as unknown as Row[])
    .filter((r) => !!r.venues)
    .map((r) => ({
      id: r.venue_id,
      role: r.role ?? "owner",
      name: r.venues!.name,
      slug: r.venues!.slug,
      city: r.venues!.city,
      // Surfaced, never filtered: an owner whose listing is hidden has to be
      // able to see it in the picker to find out why.
      listed: !r.venues!.excluded_reason && r.venues!.business_status !== "CLOSED_PERMANENTLY",
    }))
    .sort((a, b) => a.name.localeCompare(b.name));

  return NextResponse.json({ venues });
}
