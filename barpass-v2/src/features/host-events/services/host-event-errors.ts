import { NextResponse } from "next/server";

/**
 * Structured errors for the host-event routes, in the same shape the
 * concierge route returns: { error, message, retryable }. `retryable` is an
 * honest answer to "should the client offer a Try again button" — a sold-out
 * tier is not retryable, a lock contention is.
 */
export function hostEventError(
  code: string,
  status: number,
  message: string,
  { retryable = false, retryAfterSeconds }: { retryable?: boolean; retryAfterSeconds?: number } = {},
): NextResponse {
  const headers = retryAfterSeconds ? { "Retry-After": String(retryAfterSeconds) } : undefined;
  return NextResponse.json({ error: code, message, retryable }, { status, headers });
}

interface Mapped {
  status: number;
  message: string;
  retryable?: boolean;
}

/**
 * The RPCs in supabase/host_events_schema.sql raise machine-readable
 * messages (`raise exception 'sold_out'`). Postgres surfaces them verbatim
 * in error.message; this is the single place that turns them into HTTP.
 * Anything unrecognised is a 500 — never a cheerful 200.
 */
const RPC_ERRORS: Record<string, Mapped> = {
  event_not_found: { status: 404, message: "That event doesn't exist." },
  tier_not_found: { status: 404, message: "That ticket type doesn't exist." },
  event_not_published: { status: 404, message: "That event isn't published." },
  event_cancelled: { status: 410, message: "The host cancelled this event." },
  sales_not_open: { status: 409, message: "RSVPs haven't opened for this tier yet." },
  sales_closed: { status: 409, message: "RSVPs for this tier are closed." },
  paid_tier_not_enabled: {
    status: 501,
    message: "Paid tiers aren't enabled yet — payments are not live. Free RSVP tiers work now.",
  },
  already_rsvped: { status: 409, message: "You already have a spot on this tier." },
  already_waitlisted: { status: 409, message: "You're already on this waiting list." },
  sold_out: { status: 409, message: "This tier is sold out. Join the waiting list." },
  not_sold_out: { status: 409, message: "This tier still has spots — RSVP instead of queueing." },
  rsvp_not_found: { status: 404, message: "No RSVP of yours matches that." },
  rsvp_not_confirmed: { status: 409, message: "That RSVP was already released." },
  waitlist_entry_not_found: { status: 404, message: "You're not on that waiting list." },
  offer_not_found: { status: 404, message: "No live offer of yours matches that." },
  offer_expired: {
    status: 410,
    message: "Your claim window closed and the spot moved to the next person in line.",
  },
  attendee_list_private: { status: 403, message: "The host keeps this guest list private." },
  ticket_code_generation_failed: {
    status: 500,
    message: "Couldn't issue a ticket code — try again.",
    retryable: true,
  },
};

export function rpcError(rawMessage: string | undefined): NextResponse {
  const code = (rawMessage ?? "").trim();
  const mapped = RPC_ERRORS[code];
  if (!mapped) {
    console.error("[host-events] unmapped RPC error", { rawMessage });
    return hostEventError("rsvp_failed", 500, "Something went wrong on our side.", {
      retryable: true,
      retryAfterSeconds: 5,
    });
  }
  return hostEventError(code, mapped.status, mapped.message, {
    retryable: mapped.retryable ?? false,
  });
}

/** Every route parses its body the same way; keep the shape identical too. */
export async function readJson(request: Request): Promise<unknown | typeof INVALID_JSON> {
  try {
    return await request.json();
  } catch {
    return INVALID_JSON;
  }
}

export const INVALID_JSON = Symbol("invalid_json");

export function invalidJson(): NextResponse {
  return hostEventError("invalid_json", 400, "Request body wasn't valid JSON.");
}

export function invalidPayload(message?: string): NextResponse {
  return hostEventError(
    "invalid_payload",
    422,
    message ?? "The request body didn't match what this endpoint expects.",
  );
}
