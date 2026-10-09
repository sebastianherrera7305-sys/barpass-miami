/**
 * Server-side PostHog capture for Next.js route handlers.
 *
 * Why HTTP directly, not posthog-node: for the handful of events the
 * server actually originates (pass_purchased, event_ticket_purchased —
 * trustworthy because they fire AFTER Stripe reports succeeded, which
 * the client can crash between tokenize and confirm), the overhead of
 * adding the SDK outweighs the ergonomic win. A single POST per event
 * is small, dependency-free, and fire-and-forget. Rebuild as a shared
 * singleton if we end up at 20+ server events.
 *
 * Kill switch: if POSTHOG_API_KEY is unset, every call is a no-op. No
 * network traffic, no logs, nothing to clean up. Same posture as the
 * iOS side.
 */

const DEFAULT_HOST = "https://us.i.posthog.com";

export type CaptureInput = {
  event: string;
  distinctId: string;
  properties?: Record<string, unknown>;
};

/**
 * Fire-and-forget capture. Never throws, never blocks the response. If
 * PostHog is slow or down, our users don't feel it — the whole purpose
 * of this being server-side is to add a trustworthy signal, not to
 * create a new failure mode on the critical payment path.
 */
export function captureServerEvent(input: CaptureInput): void {
  const key = process.env.POSTHOG_API_KEY;
  if (!key || !input.distinctId) return;
  const host = process.env.POSTHOG_HOST || DEFAULT_HOST;

  const body = {
    api_key: key,
    event: input.event,
    distinct_id: input.distinctId,
    properties: {
      ...(input.properties ?? {}),
      $lib: "barpass-server",
      $lib_version: process.env.VERCEL_GIT_COMMIT_SHA?.slice(0, 7) ?? "unknown",
    },
    timestamp: new Date().toISOString(),
  };

  // No await — the response to the client doesn't wait on PostHog.
  // Error swallowed on purpose; a failed capture must not surface as a
  // 500 to the user whose Stripe charge already succeeded.
  fetch(`${host}/capture/`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  }).catch(() => {
    /* intentionally swallowed — see above */
  });
}
