import { NextResponse } from "next/server";
import { z } from "zod";
import { requireUser } from "@/lib/supabase/require-user";
import { createServiceRoleClient } from "@/lib/supabase/service";
import {
  hostEventError,
  invalidJson,
  invalidPayload,
  readJson,
  INVALID_JSON,
} from "@/features/host-events/services/host-event-errors";
import {
  toEventDto,
  toTierDto,
  type HostEventRow,
  type HostEventTierRow,
} from "@/features/host-events/services/host-event-dto";

/**
 * GET   /api/host-events/[id] — event + tiers + live availability.
 * PATCH /api/host-events/[id] — host-only edits, including publish/cancel
 *        and the attendee-list master switch.
 */

const patchSchema = z.object({
  title: z.string().trim().min(1).max(120).optional(),
  description: z.string().max(2000).optional(),
  startsAt: z.iso.datetime().optional(),
  endsAt: z.iso.datetime().nullable().optional(),
  status: z.enum(["draft", "published", "cancelled"]).optional(),
  attendeeListPublic: z.boolean().optional(),
  claimWindowMinutes: z.number().int().min(5).max(1440).optional(),
  coverImageUrl: z.url().nullable().optional(),
});

/** Live offers hold real seats, so availability has to count them. */
async function activeOfferCounts(
  supabase: NonNullable<ReturnType<typeof createServiceRoleClient>>,
  eventId: string,
): Promise<Map<string, number>> {
  const { data } = await supabase
    .from("host_event_waitlist")
    .select("tier_id")
    .eq("event_id", eventId)
    .eq("state", "offered")
    .gt("claim_expires_at", new Date().toISOString());
  const counts = new Map<string, number>();
  for (const row of data ?? []) {
    const tierId = row.tier_id as string;
    counts.set(tierId, (counts.get(tierId) ?? 0) + 1);
  }
  return counts;
}

export async function GET(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = createServiceRoleClient();
  if (!supabase) return hostEventError("backend_not_configured", 503, "Backend isn't configured.");

  const { data: row } = await supabase.from("host_events").select("*").eq("id", id).maybeSingle();
  if (!row) return hostEventError("event_not_found", 404, "That event doesn't exist.");
  const event = row as HostEventRow;

  // A draft or a cancelled event is the host's own business. The service-role
  // client bypasses RLS, so this route re-applies the same rule by hand.
  if (event.status !== "published") {
    const auth = await requireUser(request);
    if (!auth.ok || auth.user.id !== event.host_id) {
      return hostEventError("event_not_found", 404, "That event doesn't exist.");
    }
  }

  const [{ data: tiers }, { data: venue }, offers] = await Promise.all([
    supabase.from("host_event_tiers").select("*").eq("event_id", id).order("sort_order"),
    supabase.from("venues").select("id, name, slug").eq("id", event.venue_id).maybeSingle(),
    activeOfferCounts(supabase, id),
  ]);

  const now = new Date();
  return NextResponse.json({
    event: toEventDto(event, venue),
    tiers: ((tiers ?? []) as HostEventTierRow[]).map((t) =>
      toTierDto(t, now, offers.get(t.id) ?? 0),
    ),
    paidTiersEnabled: false,
  });
}

export async function PATCH(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const auth = await requireUser(request);
  if (!auth.ok) return auth.response;
  const { supabase, user } = auth;

  const body = await readJson(request);
  if (body === INVALID_JSON) return invalidJson();
  const parsed = patchSchema.safeParse(body);
  if (!parsed.success) return invalidPayload(parsed.error.issues[0]?.message);
  if (Object.keys(parsed.data).length === 0) {
    return hostEventError("empty_update", 422, "Nothing to update.");
  }

  const { data: existing } = await supabase
    .from("host_events")
    .select("id, host_id, status")
    .eq("id", id)
    .maybeSingle();
  // Same 404 for "doesn't exist" and "not yours" — a different answer for
  // each would turn this endpoint into an event-existence oracle.
  if (!existing || existing.host_id !== user.id) {
    return hostEventError("event_not_found", 404, "That event doesn't exist.");
  }

  const p = parsed.data;
  const update: Record<string, unknown> = { updated_at: new Date().toISOString() };
  if (p.title !== undefined) update.title = p.title;
  if (p.description !== undefined) update.description = p.description;
  if (p.startsAt !== undefined) update.starts_at = p.startsAt;
  if (p.endsAt !== undefined) update.ends_at = p.endsAt;
  if (p.attendeeListPublic !== undefined) update.attendee_list_public = p.attendeeListPublic;
  if (p.claimWindowMinutes !== undefined) update.claim_window_minutes = p.claimWindowMinutes;
  if (p.coverImageUrl !== undefined) update.cover_image_url = p.coverImageUrl;
  if (p.status !== undefined) {
    if (existing.status === "cancelled" && p.status !== "cancelled") {
      return hostEventError("event_cancelled", 409, "A cancelled event can't be reopened.");
    }
    update.status = p.status;
    update.cancelled_at = p.status === "cancelled" ? new Date().toISOString() : null;
  }

  const { data, error } = await supabase
    .from("host_events")
    .update(update)
    .eq("id", id)
    .eq("host_id", user.id)
    .select()
    .maybeSingle();

  if (error) {
    return hostEventError("update_failed", 500, error.message, { retryable: true });
  }
  if (!data) return hostEventError("event_not_found", 404, "That event doesn't exist.");

  // Cancelling frees every seat, so any queue behind it becomes moot — the
  // sweep marks lapsed offers rather than leaving them looking claimable.
  if (update.status === "cancelled") {
    await supabase.rpc("host_event_sweep_waitlist");
  }

  return NextResponse.json({ event: toEventDto(data as HostEventRow) });
}
