import { describe, it, expect } from "vitest";
import {
  entryValidityState,
  isEntryValidNow,
  salesState,
  tierAvailability,
  validateTierWindows,
} from "./host-event-rules";

// A real college night, in the shape Posh actually publishes it:
// doors 10 PM, "Free RSVP — valid 10–11 PM", sales open the afternoon before.
const NIGHT = {
  salesStartAt: "2026-09-14T16:00:00.000Z",
  salesEndAt: "2026-09-15T02:00:00.000Z",
  entryValidFrom: "2026-09-15T02:00:00.000Z", // 10 PM ET
  entryValidUntil: "2026-09-15T03:00:00.000Z", // 11 PM ET
};
const at = (iso: string) => new Date(iso);

describe("validateTierWindows", () => {
  it("accepts a real free-RSVP tier", () => {
    expect(validateTierWindows(NIGHT)).toBeNull();
  });

  it("rejects a sales window that ends before it starts", () => {
    expect(validateTierWindows({ ...NIGHT, salesEndAt: NIGHT.salesStartAt })).toBe(
      "sales_window_inverted",
    );
  });

  it("rejects an entry window that ends before it starts", () => {
    expect(
      validateTierWindows({ ...NIGHT, entryValidUntil: NIGHT.entryValidFrom }),
    ).toBe("entry_window_inverted");
  });

  it("rejects entry that is already over before sales open", () => {
    expect(
      validateTierWindows({
        ...NIGHT,
        entryValidFrom: "2026-09-14T10:00:00.000Z",
        entryValidUntil: "2026-09-14T11:00:00.000Z",
      }),
    ).toBe("entry_before_sales_start");
  });

  it("rejects a garbage timestamp instead of throwing", () => {
    expect(validateTierWindows({ ...NIGHT, salesStartAt: "not a date" })).toBe(
      "invalid_timestamp",
    );
  });
});

describe("salesState", () => {
  it("is closed before it opens and after it ends", () => {
    expect(salesState(NIGHT, at("2026-09-14T15:59:59.000Z"))).toBe("not_yet_open");
    expect(salesState(NIGHT, at("2026-09-15T02:00:01.000Z"))).toBe("closed");
  });

  it("opens exactly at the start instant and closes exactly at the end", () => {
    expect(salesState(NIGHT, at(NIGHT.salesStartAt))).toBe("open");
    // Half-open: the end instant is already closed, matching `now >= end` in SQL.
    expect(salesState(NIGHT, at(NIGHT.salesEndAt))).toBe("closed");
  });
});

describe("entryValidityState — the 'valid 10–11 PM' rule", () => {
  const { entryValidFrom: from, entryValidUntil: until } = NIGHT;

  it("is not yet valid one minute before the window", () => {
    expect(entryValidityState(from, until, at("2026-09-15T01:59:00.000Z"))).toBe("not_yet_valid");
  });

  it("is valid at the opening instant and through the window", () => {
    expect(entryValidityState(from, until, at(from))).toBe("valid");
    expect(entryValidityState(from, until, at("2026-09-15T02:30:00.000Z"))).toBe("valid");
  });

  it("expires exactly at 11 PM, not a minute after", () => {
    expect(entryValidityState(from, until, at(until))).toBe("expired");
    expect(isEntryValidNow(from, until, at(until))).toBe(false);
    expect(isEntryValidNow(from, until, at("2026-09-15T02:59:59.000Z"))).toBe(true);
  });

  it("a ticket held outside its window is worthless even though sales were open", () => {
    // The distinction the whole feature exists for: holding a valid RSVP is
    // not the same as being allowed in right now.
    expect(salesState(NIGHT, at("2026-09-14T20:00:00.000Z"))).toBe("open");
    expect(entryValidityState(from, until, at("2026-09-14T20:00:00.000Z"))).toBe("not_yet_valid");
  });
});

describe("tierAvailability", () => {
  it("counts claimed spots against the cap", () => {
    expect(tierAvailability({ quantity: 100, claimedCount: 40 })).toEqual({
      remaining: 60,
      soldOut: false,
    });
  });

  it("treats a live offer as a taken seat", () => {
    expect(tierAvailability({ quantity: 10, claimedCount: 9, activeOffers: 1 })).toEqual({
      remaining: 0,
      soldOut: true,
    });
  });

  it("never reports negative remaining if accounting drifted", () => {
    expect(tierAvailability({ quantity: 5, claimedCount: 7 }).remaining).toBe(0);
  });
});
