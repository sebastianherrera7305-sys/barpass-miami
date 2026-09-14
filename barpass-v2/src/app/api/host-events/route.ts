import { NextResponse } from "next/server";
import { z } from "zod";
import { checkRateLimit } from "@/lib/rate-limit";
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
import { validateTierWindows } from "@/features/host-events/services/host-event-rules";

/**
 * GET  /api/host-events — published, upcoming host events (public).
 * POST /api/host-events — create one, anchored to a verified venue.
 *
 * The anchor is the product decision: there is no free-text location field
 * anywhere in this API. A host picks a venue from the catalogue or there is
 * no event. Uncurated supply is what earns Posh its 1.9 on Trustpilot.
 */

const tierSchema = z.object({
  name: z.string().trim().min(1).max(60),
  description: z.string().max(300).nullable().optional(),
  priceCents: z.number().int().min(0).max(1_000_000).default(0),
  quantity: z.number().int().min(1).max(100_000),
  salesStartAt: z.iso.datetime(),
  salesEndAt: z.iso.datetime(),
  entryValidFrom: z.iso.datetime(),
  entryValidUntil: z.iso.datetime(),
  sortOrder: z.number().int().min(0).max(100).default(0),
});

const createEventSchema = z.object({
  venueId: z.uuid(),
  title: z.string().trim().min(1).max(120),
  description: z.string().max(2000).default(""),
  startsAt: z.iso.datetime(),
  endsAt: z.iso.datetime().nullable().optional(),
  attendeeListPublic: z.boolean().default(false),
  claimWindowMinutes: z.number().int().min(5).max(1440).default(30),
  coverImageUrl: z.url().nullable().optional(),
  publish: z.boolean().default(false),
  tiers: z.array(tierSchema).min(1).max(10),
});

export async function GET(request: Request) {
  const supabase = createServiceRoleClient();
  if (!supabase) return hostEventError("backend_not_configured", 503, "Backend isn't configured.");

  const url = new URL(request.url);
  const venueId = url.searchParams.get("venueId");
  const limit = Math.min(Number(url.searchParams.get("limit") ?? 50) || 50, 100);

  let query = supabase
    .from("host_events")
    .select("*")
    .eq("status", "published")
    .is("cancelled_at", null)
    .gte("starts_at", new Date(Date.now() - 12 * 3600_000).toISOString())
    .order("starts_at", { ascending: true })
    .limit(limit);
  if (venueId) query = query.eq("venue_id", venueId);

  const { data, error } = await query;
  if (error) {
    return hostEventError("list_failed", 500, error.message, { retryable: true });
  }

  const rows = (data ?? []) as HostEventRow[];
  const venueIds = [...new Set(rows.map((r) => r.venue_id))];
  const { data: venues } = venueIds.length
    ? await supabase.from("venues").select("id, name, slug").in("id", venueIds)
    : { data: [] };
  const byId = new Map((venues ?? []).map((v) => [v.id as string, v]));

  return NextResponse.json({
    events: rows.map((r) => toEventDto(r, byId.get(r.venue_id) ?? null)),
  });
}

export async function POST(request: Request) {
  const auth = await requireUser(request);
  if (!auth.ok) return auth.response;
  const { supabase, user } = auth;

  // Creating events is the cheapest possible spam vector in a product whose
  // whole pitch is "our supply is curated". 5 an hour is generous for a real
  // host and useless for a bot.
  const withinLimit = await checkRateLimit(`host-events:create:${user.id}`, {
    maxRequests: 5,
    windowSeconds: 3600,
  });
  if (!withinLimit) {
    return hostEventError("rate_limited", 429, "You've created a lot of events — try again later.", {
      retryable: true,
      retryAfterSeconds: 600,
    });
  }

  const body = await readJson(request);
  if (body === INVALID_JSON) return invalidJson();
  const parsed = createEventSchema.safeParse(body);
  if (!parsed.success) return invalidPayload(parsed.error.issues[0]?.message);
  const input = parsed.data;

  for (const tier of input.tiers) {
    const problem = validateTierWindows(tier);
    if (problem) {
      return hostEventError("invalid_tier_window", 422, `Tier "${tier.name}": ${problem}.`);
    }
  }

  // The anchor check. Both columns, both filtered — business_status answers
  // "does this place still exist" and excluded_reason answers "does it belong
  // in a nightlife app". A bare `.neq` on business_status would silently drop
  // the 171 venues Google never reached, whose value is NULL.
  const { data: venue, error: venueError } = await supabase
    .from("venues")
    .select("id, name, slug, business_status, excluded_reason")
    .eq("id", input.venueId)
    .maybeSingle();
  if (venueError) {
    return hostEventError("venue_lookup_failed", 503, venueError.message, { retryable: true });
  }
  if (!venue) {
    return hostEventError("venue_not_found", 404, "That venue isn't in the BarPass catalogue.");
  }
  if (venue.excluded_reason || venue.business_status === "CLOSED_PERMANENTLY") {
    return hostEventError("venue_not_bookable", 422, "That venue can't host BarPass events.");
  }

  const { data: eventRow, error: insertError } = await supabase
    .from("host_events")
    .insert({
      host_id: user.id,
      venue_id: input.venueId,
      title: input.title,
      description: input.description,
      starts_at: input.startsAt,
      ends_at: input.endsAt ?? null,
      status: input.publish ? "published" : "draft",
      attendee_list_public: input.attendeeListPublic,
      claim_window_minutes: input.claimWindowMinutes,
      cover_image_url: input.coverImageUrl ?? null,
    })
    .select()
    .single();

  if (insertError || !eventRow) {
    return hostEventError("create_failed", 500, insertError?.message ?? "Couldn't create the event.", {
      retryable: true,
    });
  }

  const { data: tierRows, error: tierError } = await supabase
    .from("host_event_tiers")
    .insert(
      input.tiers.map((t) => ({
        event_id: eventRow.id,
        name: t.name,
        description: t.description ?? null,
        price_cents: t.priceCents,
        quantity: t.quantity,
        sales_start_at: t.salesStartAt,
        sales_end_at: t.salesEndAt,
        entry_valid_from: t.entryValidFrom,
        entry_valid_until: t.entryValidUntil,
        sort_order: t.sortOrder,
      })),
    )
    .select();

  if (tierError || !tierRows?.length) {
    // An event with no tiers is not a half-created event, it's an unusable
    // one — roll it back rather than leave a ghost listing behind.
    await supabase.from("host_events").delete().eq("id", eventRow.id);
    return hostEventError("create_failed", 500, tierError?.message ?? "Couldn't create the tiers.", {
      retryable: true,
    });
  }

  const now = new Date();
  return NextResponse.json(
    {
      event: toEventDto(eventRow as HostEventRow, venue),
      tiers: (tierRows as HostEventTierRow[]).map((t) => toTierDto(t, now)),
      // Said once, at creation, so a host is never surprised at the door.
      paidTiersEnabled: false,
    },
    { status: 201 },
  );
}
