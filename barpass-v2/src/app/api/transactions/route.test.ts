import { describe, it, expect } from "vitest";
import { itemSchema, transactionRequestSchema } from "./route";

// Regression test for the price-manipulation fix: a modified client used to
// be able to send unitPrice: 0.01 for anything and get charged that amount.
describe("itemSchema price bounds", () => {
  it("accepts a normal item price", () => {
    const result = itemSchema.safeParse({
      productId: "vodka-soda",
      name: "Vodka Soda",
      qty: 1,
      unitPrice: 18,
    });
    expect(result.success).toBe(true);
  });

  it("rejects a near-zero manipulated price", () => {
    const result = itemSchema.safeParse({
      productId: "vip-table",
      name: "VIP Table",
      qty: 1,
      unitPrice: 0.01,
    });
    expect(result.success).toBe(false);
  });

  it("rejects an absurdly inflated price", () => {
    const result = itemSchema.safeParse({
      productId: "vodka-soda",
      name: "Vodka Soda",
      qty: 1,
      unitPrice: 999999,
    });
    expect(result.success).toBe(false);
  });

  it("rejects a negative or zero quantity", () => {
    expect(itemSchema.safeParse({ productId: "x", name: "x", qty: 0, unitPrice: 10 }).success).toBe(false);
    expect(itemSchema.safeParse({ productId: "x", name: "x", qty: -1, unitPrice: 10 }).success).toBe(false);
  });

  it("rejects an unreasonably large quantity", () => {
    const result = itemSchema.safeParse({ productId: "x", name: "x", qty: 5000, unitPrice: 10 });
    expect(result.success).toBe(false);
  });
});

describe("transactionRequestSchema", () => {
  const validItem = { productId: "vodka-soda", name: "Vodka Soda", qty: 2, unitPrice: 18 };

  it("accepts a well-formed transaction", () => {
    const result = transactionRequestSchema.safeParse({
      vendorId: "venue_123",
      staffId: "staff_1",
      items: [validItem],
      paymentMethod: "card",
      stripePaymentMethodId: "pm_123",
    });
    expect(result.success).toBe(true);
  });

  it("rejects an empty items array", () => {
    const result = transactionRequestSchema.safeParse({
      vendorId: "venue_123",
      staffId: "staff_1",
      items: [],
      paymentMethod: "card",
      stripePaymentMethodId: "pm_123",
    });
    expect(result.success).toBe(false);
  });

  it("rejects an unknown payment method", () => {
    const result = transactionRequestSchema.safeParse({
      vendorId: "venue_123",
      staffId: "staff_1",
      items: [validItem],
      paymentMethod: "crypto",
      stripePaymentMethodId: "pm_123",
    });
    expect(result.success).toBe(false);
  });

  it("propagates a bad item's price rejection through the whole request", () => {
    const result = transactionRequestSchema.safeParse({
      vendorId: "venue_123",
      staffId: "staff_1",
      items: [{ ...validItem, unitPrice: 0.01 }],
      paymentMethod: "card",
      stripePaymentMethodId: "pm_123",
    });
    expect(result.success).toBe(false);
  });
});
