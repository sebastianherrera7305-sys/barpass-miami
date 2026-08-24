import { NextResponse } from "next/server";
import { z } from "zod";
import { createClient } from "@/lib/supabase/server";

/**
 * POST /api/promos
 * Creates a promo for the caller's own venue. Same ownership model as
 * /api/events — cookie-bound session client, RLS ("owners manage own
 * venue promos", supabase/venue_owner_events_promos.sql) enforces
 * venue_owners membership.
 */

const createPromoSchema = z.object({
  venueId: z.string().uuid(),
  title: z.string().min(1),
  description: z.string().optional(),
  startsAt: z.string().datetime(),
  endsAt: z.string().datetime().nullable().optional(),
  discountText: z.string().optional(),
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
  const parsed = createPromoSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: "invalid_payload", issues: parsed.error.issues },
      { status: 422 },
    );
  }
  const { venueId, title, description, startsAt, endsAt, discountText } = parsed.data;

  const { data, error } = await supabase
    .from("promos")
    .insert({
      venue_id: venueId,
      title,
      description: description ?? null,
      starts_at: startsAt,
      ends_at: endsAt ?? null,
      discount_text: discountText ?? null,
    })
    .select()
    .single();

  if (error) {
    const status = error.code === "42501" ? 403 : 500;
    return NextResponse.json({ error: "insert_failed", message: error.message }, { status });
  }

  return NextResponse.json(data, { status: 201 });
}
