import { describe, it, expect } from "vitest";
import { topUpRequestSchema } from "./route";

describe("topUpRequestSchema", () => {
  it("accepts a normal top-up amount", () => {
    const result = topUpRequestSchema.safeParse({ amount: 50, stripePaymentMethodId: "pm_123" });
    expect(result.success).toBe(true);
  });

  it("rejects a zero or negative amount", () => {
    expect(topUpRequestSchema.safeParse({ amount: 0, stripePaymentMethodId: "pm_123" }).success).toBe(false);
    expect(topUpRequestSchema.safeParse({ amount: -20, stripePaymentMethodId: "pm_123" }).success).toBe(false);
  });

  it("rejects amounts above the $1000 cap", () => {
    const result = topUpRequestSchema.safeParse({ amount: 1001, stripePaymentMethodId: "pm_123" });
    expect(result.success).toBe(false);
  });

  it("rejects a missing payment method", () => {
    const result = topUpRequestSchema.safeParse({ amount: 50 });
    expect(result.success).toBe(false);
  });
});
