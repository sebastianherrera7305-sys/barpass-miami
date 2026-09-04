/**
 * Bounded retry for the narrow "money already moved, DB write might just be
 * a transient blip" window — audit finding, 2026-09-05: /api/transactions
 * and /api/wallet/topup charge the card FIRST, then write to Supabase, with
 * no retry at all on that write. A one-off network hiccup on Supabase's side
 * (not a real/permanent failure) turned an otherwise-successful purchase
 * into a charged-but-unrecorded order with no automatic recovery — only a
 * raw error surfaced to the client and a `stripePaymentIntentId` in the
 * response for someone to manually chase later. This doesn't replace a real
 * reconciliation job for the cases that keep failing after 3 tries, but it
 * closes the common transient case for free.
 */
export async function withRetry<Result extends { data: unknown; error: unknown }>(
  fn: () => PromiseLike<Result>,
  attempts = 3,
): Promise<Result> {
  let last: Result;
  for (let i = 0; i < attempts; i++) {
    last = await fn();
    if (!last.error) return last;
    if (i < attempts - 1) {
      await new Promise((resolve) => setTimeout(resolve, 200 * (i + 1)));
    }
  }
  return last!;
}
