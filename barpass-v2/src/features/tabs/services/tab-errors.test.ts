import { describe, it, expect } from "vitest";
import { mapChargeError, mapTabError } from "./tab-errors";
import { chargeRequestSchema } from "@/app/api/venue/tab/charge/route";
import { scanTokenSchema } from "@/app/api/tab/scan-token/route";

// Postgres wraps a plpgsql `raise exception 'x'` before PostgREST forwards it;
// these are the shapes actually seen on the wire.
const pg = (message: string) => ({ message, code: "P0001" });

describe("mapChargeError", () => {
  it("maps every documented charge failure to its stable code and status", () => {
    const cases: Array<[string, string, number]> = [
      ["token_not_found", "token_not_found", 401],
      ["token_expired", "token_expired", 410],
      ["token_already_used", "token_already_used", 409],
      ["amount_above_approved_limit", "amount_above_approved_limit", 403],
      ["insufficient_funds", "insufficient_funds", 402],
      ["wrong_venue", "wrong_venue", 403],
      ["tab_closed", "tab_closed", 409],
      ["invalid_amount", "invalid_amount", 422],
    ];
    for (const [raised, error, status] of cases) {
      expect(mapChargeError(pg(raised))).toEqual({ error, status });
    }
  });

  it("still maps when Postgres prefixes the function name", () => {
    expect(mapChargeError(pg('error in function charge_venue_tab: token_expired'))).toEqual({
      error: "token_expired",
      status: 410,
    });
  });

  it("maps a racing duplicate idempotency key to 409, not a 500", () => {
    expect(
      mapChargeError({
        code: "23505",
        message: 'duplicate key value violates unique constraint "venue_tab_charges_idempotency_key_key"',
      }),
    ).toEqual({ error: "duplicate_charge", status: 409 });
  });

  it("never leaks an unmapped Postgres message", () => {
    const mapped = mapChargeError(pg('relation "venue_tab_charges" does not exist'));
    expect(mapped).toEqual({ error: "charge_failed", status: 500 });
    expect(JSON.stringify(mapped)).not.toContain("venue_tab_charges");
  });

  it("handles a null/undefined error defensively", () => {
    expect(mapChargeError(null)).toEqual({ error: "charge_failed", status: 500 });
    expect(mapChargeError(undefined)).toEqual({ error: "charge_failed", status: 500 });
  });
});

describe("mapTabError", () => {
  it("maps the user-session RPC failures", () => {
    expect(mapTabError(pg("not_authenticated"))).toEqual({ error: "not_authenticated", status: 401 });
    expect(mapTabError(pg("not_a_member"))).toEqual({ error: "not_a_member", status: 403 });
    expect(mapTabError(pg("not_the_owner"))).toEqual({ error: "not_the_owner", status: 403 });
    expect(mapTabError(pg("tab_not_found"))).toEqual({ error: "tab_not_found", status: 404 });
    expect(mapTabError(pg("invalid_max_amount"))).toEqual({ error: "invalid_max_amount", status: 422 });
  });

  it("collapses anything unknown to a generic 500", () => {
    expect(mapTabError(pg("permission denied for function open_venue_tab"))).toEqual({
      error: "tab_operation_failed",
      status: 500,
    });
  });
});

describe("chargeRequestSchema", () => {
  const valid = {
    token: "a".repeat(48),
    venueId: "8f2b1c3d-4e5f-4a6b-8c9d-0e1f2a3b4c5d",
    amount: 18.5,
    description: "Old Fashioned",
    idempotencyKey: "pos-7-1726500000",
  };

  it("accepts a normal round", () => {
    expect(chargeRequestSchema.safeParse(valid).success).toBe(true);
    expect(chargeRequestSchema.safeParse({ ...valid, items: [{ name: "Old Fashioned", qty: 1 }] }).success).toBe(true);
  });

  it("rejects amounts the database CHECK would reject anyway", () => {
    expect(chargeRequestSchema.safeParse({ ...valid, amount: 0 }).success).toBe(false);
    expect(chargeRequestSchema.safeParse({ ...valid, amount: -5 }).success).toBe(false);
    expect(chargeRequestSchema.safeParse({ ...valid, amount: 1001 }).success).toBe(false);
  });

  it("rejects a blank description and one past the 200-char column limit", () => {
    expect(chargeRequestSchema.safeParse({ ...valid, description: "   " }).success).toBe(false);
    expect(chargeRequestSchema.safeParse({ ...valid, description: "x".repeat(201) }).success).toBe(false);
  });

  it("requires a venue uuid and an idempotency key", () => {
    expect(chargeRequestSchema.safeParse({ ...valid, venueId: "liv" }).success).toBe(false);
    expect(chargeRequestSchema.safeParse({ ...valid, idempotencyKey: "" }).success).toBe(false);
  });
});

describe("scanTokenSchema", () => {
  const tabId = "8f2b1c3d-4e5f-4a6b-8c9d-0e1f2a3b4c5d";

  it("accepts an approved ceiling inside the token's CHECK", () => {
    expect(scanTokenSchema.safeParse({ tabId, maxAmount: 60 }).success).toBe(true);
  });

  it("rejects a ceiling of zero or above 1000", () => {
    expect(scanTokenSchema.safeParse({ tabId, maxAmount: 0 }).success).toBe(false);
    expect(scanTokenSchema.safeParse({ tabId, maxAmount: 1001 }).success).toBe(false);
  });
});
