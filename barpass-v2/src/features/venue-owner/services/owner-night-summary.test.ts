import { describe, it, expect } from "vitest";
import { summariseNight, startOfVenueDay, type OrderRow, type PassRow } from "./owner-night-summary";

const order = (id: string, total: number, status = "completed"): OrderRow => ({
  id,
  total,
  status,
  created_at: "2026-09-15T02:00:00Z",
});

const pass = (id: string, amount: number, extra: Partial<PassRow> = {}): PassRow => ({
  id,
  kind: "skip_line",
  quantity: 2,
  amount,
  redeemed_at: null,
  created_at: "2026-09-15T02:00:00Z",
  source_order_id: null,
  ...extra,
});

describe("summariseNight", () => {
  it("counts a card-paid pass once, not twice", () => {
    // /api/transactions writes the order, /api/passes then mints the pass
    // against it — the old dashboard summed both and doubled the sale.
    const s = summariseNight([order("ord_1", 25)], [pass("p1", 25, { source_order_id: "ord_1" })]);
    expect(s.revenue).toBe(25);
    expect(s.orders).toBe(1);
    expect(s.passesIssued).toBe(1);
  });

  it("still counts a wallet-paid pass, which has no order row", () => {
    const s = summariseNight([], [pass("p1", 30)]);
    expect(s.revenue).toBe(30);
  });

  it("ignores an order that isn't completed", () => {
    const s = summariseNight([order("ord_1", 50, "refunded")], []);
    expect(s.revenue).toBe(0);
    expect(s.orders).toBe(0);
  });

  it("counts a pass whose backing order is not in today's window", () => {
    const s = summariseNight([], [pass("p1", 40, { source_order_id: "ord_from_yesterday" })]);
    expect(s.revenue).toBe(40);
  });

  it("reports redemptions and the head count the door plans around", () => {
    const s = summariseNight(
      [],
      [pass("p1", 20, { redeemed_at: "2026-09-15T03:00:00Z" }), pass("p2", 20, { quantity: 4 })],
    );
    expect(s.passesRedeemed).toBe(1);
    expect(s.guestsOnPasses).toBe(6);
  });

  it("tolerates numeric columns arriving as strings", () => {
    const s = summariseNight([order("o", "12.50" as unknown as number)], []);
    expect(s.revenue).toBe(12.5);
  });
});

describe("startOfVenueDay", () => {
  it("uses the venue's own timezone, not the server's", () => {
    // 03:00 UTC on the 15th is still 23:00 on the 14th in Miami — a Saturday
    // night's sales must not be split across two 'days'.
    const now = new Date("2026-09-15T03:00:00Z");
    const start = startOfVenueDay(now, "America/New_York");
    expect(start.toISOString()).toBe("2026-09-14T04:00:00.000Z");
  });

  it("falls back to server-local midnight when the timezone is unknown", () => {
    const now = new Date("2026-09-15T03:00:00Z");
    const start = startOfVenueDay(now, null);
    expect(start.getHours()).toBe(0);
  });

  it("does not throw on a bogus timezone", () => {
    expect(() => startOfVenueDay(new Date(), "Not/AZone")).not.toThrow();
  });
});
