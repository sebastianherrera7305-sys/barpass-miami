import { NextResponse } from "next/server";
import { z } from "zod";
import { createClient } from "@/lib/supabase/server";

/**
 * PATCH/DELETE /api/events/[id]
 * Same ownership model as POST /api/events — the cookie-bound session
 * client relies on RLS to reject writes to events the caller doesn't own.
 */

const patchEventSchema = z.object({
  title: z.string().min(1).optional(),
  description: z.string().optional(),
  startsAt: z.string().datetime().optional(),
  endsAt: z.string().datetime().nullable().optional(),
  coverPrice: z.number().int().nonnegative().nullable().optional(),
});

export async function PATCH(
  request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;
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
  const parsed = patchEventSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: "invalid_payload", issues: parsed.error.issues },
      { status: 422 },
    );
  }
  if (Object.keys(parsed.data).length === 0) {
    return NextResponse.json({ error: "empty_update" }, { status: 422 });
  }

  const update: Record<string, unknown> = {};
  if (parsed.data.title !== undefined) update.title = parsed.data.title;
  if (parsed.data.description !== undefined) update.description = parsed.data.description;
  if (parsed.data.startsAt !== undefined) update.starts_at = parsed.data.startsAt;
  if (parsed.data.endsAt !== undefined) update.ends_at = parsed.data.endsAt;
  if (parsed.data.coverPrice !== undefined) update.cover_price = parsed.data.coverPrice;

  const { data, error } = await supabase
    .from("events")
    .update(update)
    .eq("id", id)
    .select()
    .maybeSingle();

  if (error) {
    return NextResponse.json({ error: "update_failed", message: error.message }, { status: 500 });
  }
  if (!data) {
    // Either the row doesn't exist, or RLS silently filtered it out
    // because this user doesn't own its venue — both look identical from
    // here, and treating them the same avoids leaking which events exist.
    return NextResponse.json({ error: "not_found_or_not_owner" }, { status: 404 });
  }

  return NextResponse.json(data);
}

export async function DELETE(
  _request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;
  const supabase = await createClient();
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData?.user) {
    return NextResponse.json({ error: "not_authenticated" }, { status: 401 });
  }

  const { data, error } = await supabase
    .from("events")
    .delete()
    .eq("id", id)
    .select()
    .maybeSingle();

  if (error) {
    return NextResponse.json({ error: "delete_failed", message: error.message }, { status: 500 });
  }
  if (!data) {
    return NextResponse.json({ error: "not_found_or_not_owner" }, { status: 404 });
  }

  return NextResponse.json({ ok: true });
}
