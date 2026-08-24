import { describe, expect, it } from "vitest";
import { venueSecretMatches } from "./venue-secret";

// The failure mode this guards against is silent: a comparison that always
// returns true would accept any secret at the door and no other test in the
// suite would notice.
describe("venueSecretMatches", () => {
  const secret = "vs_live_9f2a4c8e1b7d3a6f5e0c9b8a7d6e5f4c";

  it("accepts the exact secret", () => {
    expect(venueSecretMatches(secret, secret)).toBe(true);
  });

  it("rejects a different secret of the same length", () => {
    const wrong = "vs_live_0000000000000000000000000000000f";
    expect(wrong).toHaveLength(secret.length);
    expect(venueSecretMatches(wrong, secret)).toBe(false);
  });

  it("rejects a secret differing only in the last character", () => {
    expect(venueSecretMatches(secret.slice(0, -1) + "0", secret)).toBe(false);
  });

  it("rejects a correct prefix — the exact case a timing attack builds toward", () => {
    expect(venueSecretMatches(secret.slice(0, 10), secret)).toBe(false);
  });

  it("rejects the empty string without throwing on the length mismatch", () => {
    expect(venueSecretMatches("", secret)).toBe(false);
  });

  it("rejects a much longer input without throwing", () => {
    expect(venueSecretMatches(secret + "x".repeat(500), secret)).toBe(false);
  });

  it("is case sensitive", () => {
    expect(venueSecretMatches(secret.toUpperCase(), secret)).toBe(false);
  });
});
