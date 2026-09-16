import { NextResponse } from "next/server";
import { z } from "zod";
import { checkRateLimit } from "@/lib/rate-limit";
import { requireUser } from "@/lib/supabase/require-user";
import { bearerToken, createUserScopedClient } from "@/lib/supabase/user-scoped";
import { mapTabError } from "@/features/tabs/services/tab-errors";

/**
 * The customer side of "la cuenta" (supabase/venue_tabs.sql).
 *
 * POST   /api/tab            → open (or re-open) this user's tab at a venue
 * GET    /api/tab?tabId=…    → the tab, its members and its charges
 * DELETE /api/tab?tabId=…    → close it
 *
 * All three act AS the user, never as the service role: the RPCs resolve the
 * caller through `auth.uid()`, and the read is deliberately RLS-filtered so a
 * tabId belonging to someone else's group returns nothing rather than a row.
 */

export const openTabSchema = z.object({ venueId: z.uuid() });

type OpenTabRow = { tab_id: string; join_code: string };

export async function POST(request: Request) {
  const auth = await requireUser(request);
  if (!auth.ok) return auth.response;

  const withinLimit = await checkRateLimit(`tab-open:${auth.user.id}`, {
    maxRequests: 20,
    windowSeconds: 60,
  });
  if (!withinLimit) return NextResponse.json({ error: "rate_limited" }, { status: 429 });

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }
  const parsed = openTabSchema.safeParse(body);
  if (!parsed.success) return NextResponse.json({ error: "invalid_payload" }, { status: 422 });

  const token = bearerToken(request);
  if (!token) return NextResponse.json({ error: "not_authenticated" }, { status: 401 });
  const supabase = createUserScopedClient(token);
  if (!supabase) return NextResponse.json({ error: "backend_not_configured" }, { status: 503 });

  const { data, error } = await supabase.rpc("open_venue_tab", { p_venue_id: parsed.data.venueId });
  if (error) {
    console.error("[tab] open_venue_tab failed", { code: error.code, message: error.message });
    const mapped = mapTabError(error);
    return NextResponse.json({ error: mapped.error }, { status: mapped.status });
  }
  const row = (data as OpenTabRow[] | null)?.[0];
  if (!row) return NextResponse.json({ error: "tab_operation_failed" }, { status: 500 });

  return NextResponse.json({ tabId: row.tab_id, joinCode: row.join_code });
}

export async function GET(request: Request) {
  const auth = await requireUser(request);
  if (!auth.ok) return auth.response;

  const tabId = new URL(request.url).searchParams.get("tabId");
  if (!tabId) return NextResponse.json({ error: "missing_tab_id" }, { status: 422 });

  const token = bearerToken(request);
  if (!token) return NextResponse.json({ error: "not_authenticated" }, { status: 401 });
  const supabase = createUserScopedClient(token);
  if (!supabase) return NextResponse.json({ error: "backend_not_configured" }, { status: 503 });

  // Explicit column lists, never `select *`: venue_tabs and its children have
  // columns the client has no business receiving, and a future column added to
  // the schema must not start flowing to phones by accident.
  const { data: tab, error: tabError } = await supabase
    .from("venue_tabs")
    .select("id, venue_id, owner_id, join_code, status, opened_at, closed_at")
    .eq("id", tabId)
    .maybeSingle();
  if (tabError) {
    console.error("[tab] tab read failed", { code: tabError.code, message: tabError.message });
    return NextResponse.json({ error: "read_failed" }, { status: 500 });
  }
  // RLS already hid every tab this person is not in, so "no row" and "not
  // yours" are the same answer — which is the answer we want to give.
  if (!tab) return NextResponse.json({ error: "not_found" }, { status: 404 });

  const [members, charges] = await Promise.all([
    supabase
      .from("venue_tab_members")
      .select("user_id, joined_at, left_at")
      .eq("tab_id", tabId)
      .order("joined_at", { ascending: true }),
    supabase
      .from("venue_tab_charges")
      .select("id, member_id, description, items, amount, created_at")
      .eq("tab_id", tabId)
      .order("created_at", { ascending: false }),
  ]);

  if (members.error || charges.error) {
    console.error("[tab] tab detail read failed", {
      membersCode: members.error?.code,
      chargesCode: charges.error?.code,
    });
    return NextResponse.json({ error: "read_failed" }, { status: 500 });
  }

  return NextResponse.json({
    tab: {
      id: tab.id,
      venueId: tab.venue_id,
      ownerId: tab.owner_id,
      joinCode: tab.join_code,
      status: tab.status,
      openedAt: tab.opened_at,
      closedAt: tab.closed_at,
    },
    members: (members.data ?? []).map((m) => ({
      userId: m.user_id,
      joinedAt: m.joined_at,
      leftAt: m.left_at,
    })),
    charges: (charges.data ?? []).map((c) => ({
      id: c.id,
      memberId: c.member_id,
      description: c.description,
      items: c.items,
      amount: c.amount,
      createdAt: c.created_at,
    })),
  });
}

export async function DELETE(request: Request) {
  const auth = await requireUser(request);
  if (!auth.ok) return auth.response;

  const tabId = new URL(request.url).searchParams.get("tabId");
  if (!tabId) return NextResponse.json({ error: "missing_tab_id" }, { status: 422 });

  const token = bearerToken(request);
  if (!token) return NextResponse.json({ error: "not_authenticated" }, { status: 401 });
  const supabase = createUserScopedClient(token);
  if (!supabase) return NextResponse.json({ error: "backend_not_configured" }, { status: 503 });

  const { error } = await supabase.rpc("close_venue_tab", { p_tab_id: tabId });
  if (error) {
    console.error("[tab] close_venue_tab failed", { code: error.code, message: error.message });
    const mapped = mapTabError(error);
    return NextResponse.json({ error: mapped.error }, { status: mapped.status });
  }
  return NextResponse.json({ success: true });
}
