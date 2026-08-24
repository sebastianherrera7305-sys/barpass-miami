import { createHash, timingSafeEqual } from "node:crypto";

/**
 * Constant-time comparison of a caller-supplied venue secret against the one
 * on record.
 *
 * A plain `!==` returns as soon as two bytes differ, so response time leaks
 * how many leading characters were correct — enough to recover a secret one
 * character at a time. Both endpoints that check `x-venue-secret` are rate
 * limited, which makes that attack slow rather than impossible; this closes
 * it outright.
 *
 * Both sides are hashed first because `timingSafeEqual` throws on
 * length-mismatched buffers — comparing the digests keeps the inputs a fixed
 * 32 bytes and avoids leaking the secret's length through that throw.
 */
export function venueSecretMatches(provided: string, expected: string): boolean {
  const providedHash = createHash("sha256").update(provided).digest();
  const expectedHash = createHash("sha256").update(expected).digest();
  return timingSafeEqual(providedHash, expectedHash);
}
