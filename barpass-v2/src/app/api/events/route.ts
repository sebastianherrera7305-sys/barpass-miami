import { NextResponse } from "next/server";
import { z } from "zod";
import { createClient } from "@/lib/supabase/server";

/**
 * POST /api/events
 * Creates an event for the caller's own venue. Uses the cookie-bound
 * server Supabase client (the signed-in venue owner's session), not the
 * service role — RLS ("owners manage own venue events",
 * supabase/venue_owner_events_promos.sql) enforces that venue_id must
 * match a venue_owners row for this user, so ownership is checked by the
 * database, not by this route's code.
 */

const createEventSchema = z.object({
  venueId: z.string().uuid(),
  title: z.string().min(1),
  description: z.string().optional(),
  startsAt: z.string().datetime(),
  endsAt: z.string().datetime().nullable().optional(),
  coverPrice: z.number().int().nonnegative().nullable().optional(),
});

export async function POST(request: Request) {
  const supabase = await createClient();
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData?.user) {
    return NextResponse.json({ error: "not_authenticated" }, { status: 401 });
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }
  const parsed = createEventSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: "invalid_payload", issues: parsed.error.issues },
      { status: 422 },
    );
  }
  const { venueId, title, description, startsAt, endsAt, coverPrice } = parsed.data;

  const { data, error } = await supabase
    .from("events")
    .insert({
      venue_id: venueId,
      title,
      description: description ?? "",
      starts_at: startsAt,
      ends_at: endsAt ?? null,
      cover_price: coverPrice ?? null,
    })
    .select()
    .single();

  if (error) {
    // RLS denies the insert (not this venue's owner) as a 0-row failure
    // that surfaces here as a generic policy error — not distinguishable
    // from other insert failures without parsing Postgres error codes, so
    // we return a flat 403 for RLS-shaped errors and 500 otherwise.
    const status = error.code === "42501" ? 403 : 500;
    return NextResponse.json({ error: "insert_failed", message: error.message }, { status });
  }

  return NextResponse.json(data, { status: 201 });
}
