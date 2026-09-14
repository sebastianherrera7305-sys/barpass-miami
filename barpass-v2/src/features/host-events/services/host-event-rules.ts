/**
 * Pure rules for host events: sales windows, entry-validity windows, tier
 * availability and the waitlist queue.
 *
 * The DATABASE is the authority — supabase/host_events_schema.sql holds the
 * same rules inside SECURITY DEFINER RPCs, under row locks, and is the only
 * thing that can actually mint an RSVP. This module exists so the API and the
 * clients can (a) reject a bad tier definition before it reaches Postgres and
 * (b) tell a user what state they are in ("opens in 20 min", "you're #4")
 * without a round trip per question. If the two ever disagree, the SQL wins
 * and this file is the bug.
 */

export type SalesState = "not_yet_open" | "open" | "closed";
export type EntryValidityState = "not_yet_valid" | "valid" | "expired";

export interface TierWindows {
  salesStartAt: string;
  salesEndAt: string;
  entryValidFrom: string;
  entryValidUntil: string;
}

export type WaitlistState = "waiting" | "offered" | "claimed" | "expired" | "left";

export interface WaitlistEntry {
  id: string;
  userId: string;
  /** ISO timestamp. Queue order is join time, tie-broken by id. Nothing else. */
  joinedAt: string;
  state: WaitlistState;
  claimExpiresAt?: string | null;
}

export interface TierCapacity {
  quantity: number;
  claimedCount: number;
  /** Live offers hold a real seat until their claim window lapses. */
  activeOffers?: number;
}

function ms(iso: string): number {
  const t = new Date(iso).getTime();
  if (Number.isNaN(t)) throw new RangeError(`invalid timestamp: ${iso}`);
  return t;
}

// ── Windows ────────────────────────────────────────────────────────────

export type WindowProblem =
  | "sales_window_inverted"
  | "entry_window_inverted"
  | "entry_before_sales_start"
  | "invalid_timestamp";

/**
 * Checks a tier definition before it is written. Mirrors the CHECK
 * constraints on host_event_tiers, plus one rule the database deliberately
 * does not enforce: entry may not end before sales even begin, which is
 * always a typo rather than a real configuration.
 */
export function validateTierWindows(w: TierWindows): WindowProblem | null {
  let salesStart: number, salesEnd: number, entryFrom: number, entryUntil: number;
  try {
    salesStart = ms(w.salesStartAt);
    salesEnd = ms(w.salesEndAt);
    entryFrom = ms(w.entryValidFrom);
    entryUntil = ms(w.entryValidUntil);
  } catch {
    return "invalid_timestamp";
  }
  if (salesEnd <= salesStart) return "sales_window_inverted";
  if (entryUntil <= entryFrom) return "entry_window_inverted";
  if (entryUntil <= salesStart) return "entry_before_sales_start";
  return null;
}

/** Is this tier claimable right now? Half-open: [start, end). */
export function salesState(w: Pick<TierWindows, "salesStartAt" | "salesEndAt">, now: Date): SalesState {
  const t = now.getTime();
  if (t < ms(w.salesStartAt)) return "not_yet_open";
  if (t >= ms(w.salesEndAt)) return "closed";
  return "open";
}

/**
 * The "valid 10–11 PM" part, evaluated at the door. Half-open on both ends
 * the same way sales are: a ticket valid until 11:00 is not valid at 11:00.
 */
export function entryValidityState(
  validFrom: string,
  validUntil: string,
  now: Date,
): EntryValidityState {
  const t = now.getTime();
  if (t < ms(validFrom)) return "not_yet_valid";
  if (t >= ms(validUntil)) return "expired";
  return "valid";
}

export function isEntryValidNow(validFrom: string, validUntil: string, now: Date): boolean {
  return entryValidityState(validFrom, validUntil, now) === "valid";
}

// ── Capacity ───────────────────────────────────────────────────────────

export interface Availability {
  remaining: number;
  soldOut: boolean;
}

/**
 * Seats a walk-up could take right now. Outstanding offers are subtracted:
 * a seat that has been offered to a waitlister is not available, or two
 * people would be promised the same one.
 */
export function tierAvailability(tier: TierCapacity): Availability {
  const remaining = Math.max(
    0,
    tier.quantity - tier.claimedCount - (tier.activeOffers ?? 0),
  );
  return { remaining, soldOut: remaining === 0 };
}

// ── Waitlist ───────────────────────────────────────────────────────────

/** Live entries, in queue order: earliest join first, id as the tie-break. */
export function orderQueue(entries: readonly WaitlistEntry[]): WaitlistEntry[] {
  return entries
    .filter((e) => e.state === "waiting" || e.state === "offered")
    .sort((a, b) => {
      const d = ms(a.joinedAt) - ms(b.joinedAt);
      return d !== 0 ? d : a.id.localeCompare(b.id);
    });
}

export function isOfferClaimable(entry: WaitlistEntry, now: Date): boolean {
  return (
    entry.state === "offered" &&
    entry.claimExpiresAt != null &&
    ms(entry.claimExpiresAt) > now.getTime()
  );
}

export function claimExpiryFor(offeredAt: Date, claimWindowMinutes: number): Date {
  return new Date(offeredAt.getTime() + claimWindowMinutes * 60_000);
}

/**
 * Applies the passage of time to the queue: an offer whose window lapsed is
 * expired, and it does NOT go back to waiting — the holder loses their turn
 * and the seat moves down the queue. Returns a new array; never mutates.
 */
export function expireLapsedOffers(
  entries: readonly WaitlistEntry[],
  now: Date,
): WaitlistEntry[] {
  return entries.map((e) =>
    e.state === "offered" && !isOfferClaimable(e, now)
      ? { ...e, state: "expired" as const }
      : { ...e },
  );
}

/** 1-based position among live entries, or null if this user isn't queued. */
export function queuePosition(
  entries: readonly WaitlistEntry[],
  userId: string,
  now: Date,
): number | null {
  const live = orderQueue(expireLapsedOffers(entries, now));
  const idx = live.findIndex((e) => e.userId === userId);
  return idx === -1 ? null : idx + 1;
}

export interface OfferPlan {
  /** Entries that should move waiting → offered, in queue order. */
  offers: WaitlistEntry[];
  /** The queue after expiries and the new offers are applied. */
  entries: WaitlistEntry[];
}

/**
 * What host_event_offer_next() does, in the small: expire what lapsed, then
 * walk the queue handing out exactly as many offers as there are free seats.
 * Seats already held by a live offer are not re-offered.
 */
export function planOffers(
  entries: readonly WaitlistEntry[],
  tier: TierCapacity,
  now: Date,
  claimWindowMinutes: number,
): OfferPlan {
  const swept = expireLapsedOffers(entries, now);
  const liveOffers = swept.filter((e) => e.state === "offered").length;
  const { remaining } = tierAvailability({
    quantity: tier.quantity,
    claimedCount: tier.claimedCount,
    activeOffers: liveOffers,
  });

  const expiresAt = claimExpiryFor(now, claimWindowMinutes).toISOString();
  const waiting = orderQueue(swept).filter((e) => e.state === "waiting");
  const chosen = waiting.slice(0, remaining);
  const chosenIds = new Set(chosen.map((e) => e.id));

  const next = swept.map((e) =>
    chosenIds.has(e.id)
      ? { ...e, state: "offered" as const, claimExpiresAt: expiresAt }
      : e,
  );
  return {
    offers: next.filter((e) => chosenIds.has(e.id)),
    entries: next,
  };
}
