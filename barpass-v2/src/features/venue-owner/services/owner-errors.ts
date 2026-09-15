import { NextResponse } from "next/server";

/**
 * Structured errors for the venue-owner routes, in the same
 * `{ error, message, retryable }` shape the concierge and host-event routes
 * return. `retryable` answers "should the dashboard offer a Try again button"
 * — a missing venue_owners row is not retryable, a Supabase timeout is.
 */
export function ownerError(
  code: string,
  status: number,
  message: string,
  { retryable = false }: { retryable?: boolean } = {},
): NextResponse {
  return NextResponse.json({ error: code, message, retryable }, { status });
}
