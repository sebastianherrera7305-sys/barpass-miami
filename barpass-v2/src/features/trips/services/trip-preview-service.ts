import { createServiceRoleClient } from "@/lib/supabase/service";

/**
 * Public preview of a Trip — the ONLY shape ever exposed to the unauthenticated
 * web landing (`/trip/[id]`). Deliberately excludes everything not needed to
 * render an invitation card: no `stops` (itinerary), no `member_ids` /
 * `co_organizer_ids` / `pending_requests` (real user ids), no `creator_id`,
 * no `invite_code`. Adding a field here is a security decision — narrow the
 * SELECT in getTripPreview() to match, never widen it by selecting `*`.
 */
export interface TripPreviewDTO {
  title: string;
  destinationCity: string;
  coverImage: string | null;
  startDate: string;
  endDate: string;
  memberCount: number;
  visibility: "private" | "semi_open" | "public";
}

/**
 * Resolves a public trip preview.
 *
 * SECURITY MODEL (S3, deliberate interim state — see
 * PHASE_1_TRIP_LANDING_AUDIT.md): trips.trips_select RLS only allows the
 * anon key to read rows where `visibility <> 'private'`, but visibility
 * defaults to 'private' and that's what most real shared trips are — an
 * anon-key read would 404 on the exact links this page exists to serve. This
 * function uses the service role (bypasses RLS) and returns an explicit,
 * narrow DTO instead: knowledge of the trip's UUID is what gates access,
 * the same trust model as an unlisted Notion/Google Docs link. No visibility
 * check is applied — a 'private' trip's *preview* (never its itinerary or
 * membership) is intentionally reachable by anyone holding the id.
 *
 * ARCHITECTURE (per Staff Engineer review, ahead of S4/Referral): the public
 * identifier this function resolves is a bare trip UUID today. That
 * coupling is intentionally confined to THIS function — the landing page
 * only ever calls `getTripPreview(id)` and knows nothing about how `id` maps
 * to a row. S4 can introduce a `trip_share_links` table (revocable, expiring,
 * attributable public tokens) and change this function's resolution from
 * "id is the trip's own uuid" to "id is a token → look up trip_id" without
 * touching the landing page, generateMetadata, or the DTO shape at all.
 */
export async function getTripPreview(tripId: string): Promise<TripPreviewDTO | null> {
  const supabase = createServiceRoleClient();
  if (!supabase) return null;

  // Explicit column list — never `select("*")`. member_ids is fetched only
  // to compute a count; it is never placed on the returned DTO, so even a
  // future bug in this function can't leak it (the DTO type has no field to
  // put it in).
  const { data, error } = await supabase
    .from("trips")
    .select("title, destination_city, cover_image, start_date, end_date, visibility, member_ids")
    .eq("id", tripId)
    .maybeSingle();

  if (error || !data) return null;

  return {
    title: data.title,
    destinationCity: data.destination_city,
    coverImage: data.cover_image,
    startDate: data.start_date,
    endDate: data.end_date,
    memberCount: Array.isArray(data.member_ids) ? data.member_ids.length : 0,
    visibility: data.visibility,
  };
}
