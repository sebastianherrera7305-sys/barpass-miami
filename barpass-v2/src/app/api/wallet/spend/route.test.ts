import { describe, it, expect } from "vitest";
import { spendRequestSchema } from "./route";

describe("spendRequestSchema", () => {
  it("accepts a normal spend amount", () => {
    expect(spendRequestSchema.safeParse({ amount: 25 }).success).toBe(true);
  });

  it("rejects a zero or negative amount", () => {
    expect(spendRequestSchema.safeParse({ amount: 0 }).success).toBe(false);
    expect(spendRequestSchema.safeParse({ amount: -10 }).success).toBe(false);
  });

  it("rejects a missing amount", () => {
    expect(spendRequestSchema.safeParse({}).success).toBe(false);
  });
});
