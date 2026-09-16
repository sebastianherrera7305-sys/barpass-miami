/**
 * Postgres exceptions → HTTP, for the venue-tab RPCs.
 *
 * The raw Postgres message NEVER reaches the client. A PostgrestError carries
 * table names, constraint names and sometimes the offending row, and the bar's
 * tablet is the least trusted device we ship to: whoever holds the venue
 * secret would otherwise learn the shape of the schema one failed scan at a
 * time. The client gets a stable code from the lists below and nothing else;
 * anything unrecognised collapses to a generic failure and is logged
 * server-side instead.
 */

export type MappedError = { error: string; status: number };

/** Something Supabase can hand back from `.rpc()`. */
export type RpcErrorLike = { message?: string | null; code?: string | null } | null | undefined;

/**
 * Charge failures (supabase/venue_tabs.sql § 8). Ordering matters only in that
 * each key must be matched as a whole word-ish substring of the Postgres
 * message, which looks like `charge_venue_tab: token_expired` or just the bare
 * condition depending on how PostgREST wraps it.
 */
const CHARGE_ERRORS: Record<string, number> = {
  // A token that does not exist is indistinguishable from a forged one: this
  // is an authentication failure, not a "not found".
  token_not_found: 401,
  token_expired: 410,
  token_already_used: 409,
  amount_above_approved_limit: 403,
  insufficient_funds: 402,
  wrong_venue: 403,
  tab_closed: 409,
  invalid_amount: 422,
};

const TAB_ERRORS: Record<string, number> = {
  not_authenticated: 401,
  not_a_member: 403,
  not_the_owner: 403,
  tab_not_found: 404,
  tab_closed: 409,
  invalid_max_amount: 422,
};

function match(table: Record<string, number>, error: RpcErrorLike): MappedError | null {
  const message = error?.message ?? "";
  for (const [code, status] of Object.entries(table)) {
    if (message.includes(code)) return { error: code, status };
  }
  return null;
}

/**
 * Maps a `charge_venue_tab` failure. Falls back to `charge_failed` / 500 so an
 * unmapped Postgres error can never leak through as prose.
 */
export function mapChargeError(error: RpcErrorLike): MappedError {
  const known = match(CHARGE_ERRORS, error);
  if (known) return known;
  // 23505 = unique_violation. The RPC returns the existing charge for a
  // repeated idempotency key, so this only fires when two identical requests
  // race past that lookup at the same instant. The first one won; the second
  // must not be reported as a second drink.
  if (error?.code === "23505") return { error: "duplicate_charge", status: 409 };
  return { error: "charge_failed", status: 500 };
}

/** Maps a user-session tab RPC failure (open / join / issue token / close). */
export function mapTabError(error: RpcErrorLike): MappedError {
  return match(TAB_ERRORS, error) ?? { error: "tab_operation_failed", status: 500 };
}
