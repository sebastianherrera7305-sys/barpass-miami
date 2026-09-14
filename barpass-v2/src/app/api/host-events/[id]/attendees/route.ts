import { NextResponse } from "next/server";
import { requireUser } from "@/lib/supabase/require-user";
import { hostEventError, rpcError } from "@/features/host-events/services/host-event-errors";

/**
 * GET /api/host-events/[id]/attendees — "who's going".
 *
 * Authenticated only, with no anonymous path of any kind. This list ties a
 * named person to a venue on a date, which is exactly the shape of data that
 * leaked when `venue_media.user_id` was anon-readable and handed out people's
 * location history. `host_event_rsvps` therefore has no anon RLS policy at
 * all, and the list is assembled by host_event_attendees(), a SECURITY
 * DEFINER function whose EXECUTE is revoked from anon AND authenticated —
 * only the service role behind this route can call it.
 *
 * Two switches, both required, matching Posh's own privacy documentation:
 * the ORGANISER holds the master switch (host_events.attendee_list_public)
 * and each ATTENDEE holds their own (rsvps.show_on_attendee_list). The host
 * sees every confirmed guest regardless — they work the door — with
 * hiddenFromPublic flagged so the UI can say who opted out.
 */

interface AttendeeRow {
  user_id: string;
  display_name: string;
  avatar_url: string | null;
  tier_name: string;
  hidden_from_public: boolean;
}

export async function GET(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const auth = await requireUser(request);
  if (!auth.ok) return auth.response;
  const { supabase, user } = auth;

  const { data, error } = await supabase.rpc("host_event_attendees", {
    p_user_id: user.id,
    p_event_id: id,
  });
  if (error) return rpcError(error.message);

  const rows = (data ?? []) as AttendeeRow[];
  const { data: event } = await supabase
    .from("host_events")
    .select("host_id, attendee_list_public")
    .eq("id", id)
    .maybeSingle();
  if (!event) return hostEventError("event_not_found", 404, "That event doesn't exist.");

  return NextResponse.json({
    attendeeListPublic: event.attendee_list_public,
    viewerIsHost: event.host_id === user.id,
    count: rows.length,
    attendees: rows.map((r) => ({
      userId: r.user_id,
      displayName: r.display_name,
      avatarUrl: r.avatar_url,
      tierName: r.tier_name,
      hiddenFromPublic: r.hidden_from_public,
    })),
  });
}
