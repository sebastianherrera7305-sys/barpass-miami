/**
 * The support address, written down exactly once.
 *
 * WHY A CONSTANT AND NOT A LITERAL IN THE PAGE
 * Three different addresses are published today — `legal@barpass.app` in
 * the Terms, `privacy@barpass.app` in the Privacy Policy, and
 * `hola@barpass.app` in `src/config/site.ts`. One person answers all of
 * them, which means two of the three are decoration. When the mailbox is
 * finally decided, it has to change in one place, and anything that wants
 * to point at support (the legal pages, the iOS profile screen, App Store
 * Connect's Support URL) should import this rather than retype it.
 *
 * ⚠ VERIFIED BROKEN ON 2026-09-19 — `barpass.app` has NO MX records, so
 * every address at this domain bounces. Publishing an address that
 * bounces is worse than publishing none: it looks like compliance and
 * fails the one test Apple actually runs (App Review Guideline 1.2 asks
 * for contact information, and a reviewer may write to it). This constant
 * is deliberately the only thing that has to change once mail is set up —
 * but the page it feeds is a promise the domain cannot keep until then.
 * Confirm with: send mail from an outside mailbox and wait for the bounce.
 */
export const SUPPORT_EMAIL = "support@barpass.app";

/** Shown under the heading, same as the legal pages. */
export const CONTACT_LAST_UPDATED = "September 20, 2026";

/**
 * A mailto with the subject already filled in.
 *
 * The subject is the only triage this mailbox has: with no ticketing
 * system behind it, "Content report" in the subject line is what lets a
 * takedown be found among receipts and venue questions. Body text is
 * prefilled only where it asks for the facts a report is useless without
 * (which venue, which night) — never with anything about the sender.
 */
export function supportMailto(subject: string, body?: string): string {
  const params = new URLSearchParams({ subject });
  if (body) params.set("body", body);
  // URLSearchParams encodes spaces as "+", which mail clients render
  // literally in a subject line. Newlines in a body must be %0A, not "+".
  const query = params.toString().replace(/\+/g, "%20");
  return `mailto:${SUPPORT_EMAIL}?${query}`;
}
