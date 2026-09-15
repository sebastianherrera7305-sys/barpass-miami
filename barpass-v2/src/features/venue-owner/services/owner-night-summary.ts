/**
 * Tonight's numbers for one venue, computed in one place so the owner
 * dashboard and the door-staff stats endpoint can never disagree.
 *
 * THE DOUBLE-COUNT THIS FIXES: a card-paid pass writes BOTH an `orders` row
 * (/api/transactions, after Stripe confirms) AND a `passes` row
 * (/api/passes, which refuses to mint a pass without a verified
 * `source_order_id` pointing at that order). Summing orders.total +
 * passes.amount therefore reported every card sale twice. A wallet-paid pass
 * has `source_wallet_transaction_id` instead and no order row, so it must
 * still be counted from the pass. The rule: count a pass's amount only when
 * it is not backed by an order that is already in the orders total.
 */

export interface OrderRow {
  id: string;
  total: number | string;
  status?: string | null;
  created_at: string;
}

export interface PassRow {
  id: string;
  kind: string;
  quantity: number;
  amount: number | string;
  redeemed_at: string | null;
  created_at: string;
  source_order_id?: string | null;
}

export interface NightSummary {
  /** Dollars taken today, each sale counted once. */
  revenue: number;
  orders: number;
  passesIssued: number;
  passesRedeemed: number;
  /** People those passes cover — what the door actually plans around. */
  guestsOnPasses: number;
}

function money(v: number | string): number {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}

/** Only completed orders are revenue. Today `/api/transactions` writes nothing
 *  else, but a future refund state must not quietly inflate the number. */
function isCountableOrder(o: OrderRow): boolean {
  return (o.status ?? "completed") === "completed";
}

export function summariseNight(orders: OrderRow[], passes: PassRow[]): NightSummary {
  const countableOrders = orders.filter(isCountableOrder);
  const orderIds = new Set(countableOrders.map((o) => o.id));

  const orderRevenue = countableOrders.reduce((sum, o) => sum + money(o.total), 0);
  const passRevenue = passes.reduce((sum, p) => {
    const backedByCountedOrder = !!p.source_order_id && orderIds.has(p.source_order_id);
    return backedByCountedOrder ? sum : sum + money(p.amount);
  }, 0);

  return {
    revenue: Math.round((orderRevenue + passRevenue) * 100) / 100,
    orders: countableOrders.length,
    passesIssued: passes.length,
    passesRedeemed: passes.filter((p) => p.redeemed_at).length,
    guestsOnPasses: passes.reduce((sum, p) => sum + (Number.isFinite(p.quantity) ? p.quantity : 0), 0),
  };
}

/**
 * Start of "today" for a venue, in the venue's OWN timezone — the catalogue
 * spans 23 cities, and a Miami bar's Saturday is not a server's UTC Saturday.
 * Falls back to the server's local midnight when the venue has no timezone,
 * which is the previous behaviour.
 */
export function startOfVenueDay(now: Date, timezone: string | null): Date {
  if (!timezone) {
    const local = new Date(now);
    local.setHours(0, 0, 0, 0);
    return local;
  }
  try {
    const parts = new Intl.DateTimeFormat("en-CA", {
      timeZone: timezone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
      hour12: false,
    }).formatToParts(now);
    const get = (t: string) => Number(parts.find((p) => p.type === t)?.value ?? "0");
    const secondsIntoDay = get("hour") * 3600 + get("minute") * 60 + get("second");
    return new Date(now.getTime() - secondsIntoDay * 1000);
  } catch {
    const local = new Date(now);
    local.setHours(0, 0, 0, 0);
    return local;
  }
}
