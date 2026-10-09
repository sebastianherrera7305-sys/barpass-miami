import { describe, it, expect, vi, beforeEach } from "vitest";

// Prove that a second request with the SAME Idempotency-Key never charges
// the card twice. The route calls stripe.paymentIntents.create with a
// second-arg `{ idempotencyKey }` option (added in this commit) — this
// test asserts that option is set, is stable across retries of one
// logical attempt, is namespaced per user (two users with identical
// client keys get DIFFERENT Stripe keys), and that the DB pre-check
// short-circuits a sequential retry so the second request doesn't even
// hit Stripe.

const createPaymentIntentMock = vi.fn();
const maybeSingleMock = vi.fn();
const supabaseInsertMock = vi.fn();

// vi.mock calls are hoisted — the factories need to be self-contained
// (no outer-scope var references). We expose the stubs through globalThis
// so the tests can reach them.
vi.mock("stripe", () => {
  class StripeMock {
    paymentIntents = {
      create: (...args: unknown[]) =>
        (globalThis as unknown as { __createPIM: (...args: unknown[]) => unknown }).__createPIM(
          ...args,
        ),
    };
  }
  return { default: StripeMock };
});

vi.mock("@/lib/supabase/require-user", () => ({
  requireUser: async (request: Request) => {
    const userId = request.headers.get("x-test-user") || "user_a";
    return {
      ok: true,
      user: { id: userId },
      supabase: {
        from: () => ({
          select: () => ({
            eq: () => ({
              eq: () => ({
                maybeSingle: () =>
                  (globalThis as unknown as { __maybeSingle: () => Promise<unknown> }).__maybeSingle(),
              }),
            }),
          }),
          insert: () => ({
            select: () => ({
              single: () =>
                (globalThis as unknown as { __insert: () => Promise<unknown> }).__insert(),
            }),
          }),
        }),
      },
    };
  },
}));

vi.mock("@/lib/age-verification", () => ({
  requireAgeVerified21: async () => null,
}));

vi.mock("@/lib/rate-limit", () => ({
  checkRateLimit: async () => true,
}));

vi.mock("@/lib/with-retry", () => ({
  withRetry: async (fn: () => Promise<unknown>) => fn(),
}));

// Hook the stubs onto globalThis after vi.mock has hoisted the factories.
(globalThis as unknown as { __createPIM: unknown }).__createPIM = createPaymentIntentMock;
(globalThis as unknown as { __maybeSingle: unknown }).__maybeSingle = maybeSingleMock;
(globalThis as unknown as { __insert: unknown }).__insert = supabaseInsertMock;

process.env.STRIPE_SECRET_KEY = "sk_test_idempotency_fixture";

async function loadPost() {
  // Dynamic import so the mocks are in place before the module loads.
  const { POST } = await import("./route");
  return POST;
}

function makeRequest(opts: {
  idempotencyKey?: string;
  user?: string;
  amount?: number;
}): Request {
  const unitPrice = opts.amount ?? 25;
  const headers: Record<string, string> = {
    "content-type": "application/json",
    "x-test-user": opts.user ?? "user_a",
  };
  if (opts.idempotencyKey) headers["idempotency-key"] = opts.idempotencyKey;
  return new Request("https://barpass.test/api/transactions", {
    method: "POST",
    headers,
    body: JSON.stringify({
      vendorId: "venue_demo",
      staffId: "staff_demo",
      items: [{ productId: "vodka-soda", name: "Vodka Soda", qty: 1, unitPrice }],
      paymentMethod: "card",
      stripePaymentMethodId: "pm_test_card_visa",
    }),
  });
}

describe("POST /api/transactions — Stripe idempotency", () => {
  beforeEach(() => {
    createPaymentIntentMock.mockReset();
    maybeSingleMock.mockReset();
    supabaseInsertMock.mockReset();
  });

  it("passes the Idempotency-Key, namespaced by user id, to Stripe", async () => {
    maybeSingleMock.mockResolvedValue({ data: null, error: null });
    createPaymentIntentMock.mockResolvedValue({ id: "pi_abc", status: "succeeded" });
    supabaseInsertMock.mockResolvedValue({
      data: { id: "txn_abc", status: "completed" },
      error: null,
    });

    const POST = await loadPost();
    const res = await POST(makeRequest({ idempotencyKey: "client_xyz_123", user: "user_a" }));
    expect([200, 201]).toContain(res.status);

    expect(createPaymentIntentMock).toHaveBeenCalledTimes(1);
    const [, options] = createPaymentIntentMock.mock.calls[0];
    expect(options).toEqual({ idempotencyKey: "bp:user_a:client_xyz_123" });
  });

  it("sends the SAME Stripe idempotency key when the client retries the same attempt", async () => {
    // Simulate the dropped-response retry: first request's DB pre-check
    // sees no prior row (both races pass this check); the second request
    // sees the row inserted by the first and short-circuits.
    maybeSingleMock
      .mockResolvedValueOnce({ data: null, error: null })
      .mockResolvedValueOnce({ data: { id: "txn_abc", status: "completed" }, error: null });
    createPaymentIntentMock.mockResolvedValue({ id: "pi_abc", status: "succeeded" });
    supabaseInsertMock.mockResolvedValue({
      data: { id: "txn_abc", status: "completed" },
      error: null,
    });

    const POST = await loadPost();

    await POST(makeRequest({ idempotencyKey: "stable_key_1", user: "user_a" }));
    await POST(makeRequest({ idempotencyKey: "stable_key_1", user: "user_a" }));

    // Sequential retry — second request short-circuits on the DB pre-check,
    // so Stripe is only called once overall. The one call carries the
    // namespaced key.
    expect(createPaymentIntentMock).toHaveBeenCalledTimes(1);
    expect(createPaymentIntentMock.mock.calls[0][1]).toEqual({
      idempotencyKey: "bp:user_a:stable_key_1",
    });
  });

  it("even in a concurrent-request race (both see null in pre-check), Stripe gets the SAME key for both — so Stripe itself serializes and does NOT double-charge", async () => {
    // Both requests see no prior order row — this is the race the DB
    // pre-check CANNOT catch on its own. Prior to this fix, both would
    // call stripe.create with no idempotencyKey option and both would
    // charge. After the fix, both requests pass the SAME key to Stripe,
    // and Stripe itself returns the same PaymentIntent to both.
    maybeSingleMock.mockResolvedValue({ data: null, error: null });

    const sentKeys: string[] = [];
    createPaymentIntentMock.mockImplementation(
      async (_params: unknown, options: { idempotencyKey?: string }) => {
        sentKeys.push(options?.idempotencyKey ?? "<MISSING>");
        return { id: "pi_abc", status: "succeeded" };
      },
    );
    supabaseInsertMock.mockResolvedValue({
      data: { id: "txn_abc", status: "completed" },
      error: null,
    });

    const POST = await loadPost();
    await Promise.all([
      POST(makeRequest({ idempotencyKey: "race_key", user: "user_a" })),
      POST(makeRequest({ idempotencyKey: "race_key", user: "user_a" })),
    ]);

    expect(sentKeys).toHaveLength(2);
    expect(sentKeys[0]).toBe("bp:user_a:race_key");
    expect(sentKeys[1]).toBe("bp:user_a:race_key");
    // Both requests send the same key — Stripe itself dedups and returns
    // the same PaymentIntent to both. Without the second-arg option (the
    // bug this test exists to prevent) the key would be <MISSING>.
    expect(sentKeys.every((k) => k === "bp:user_a:race_key")).toBe(true);
  });

  it("namespaces by user — two different users submitting IDENTICAL client keys get DIFFERENT Stripe keys", async () => {
    maybeSingleMock.mockResolvedValue({ data: null, error: null });
    const sentKeys: string[] = [];
    createPaymentIntentMock.mockImplementation(
      async (_params: unknown, options: { idempotencyKey?: string }) => {
        sentKeys.push(options?.idempotencyKey ?? "<MISSING>");
        return { id: "pi_abc", status: "succeeded" };
      },
    );
    supabaseInsertMock.mockResolvedValue({
      data: { id: "txn_abc", status: "completed" },
      error: null,
    });

    const POST = await loadPost();
    await POST(makeRequest({ idempotencyKey: "shared_raw_key", user: "user_a" }));
    await POST(makeRequest({ idempotencyKey: "shared_raw_key", user: "user_b" }));

    expect(sentKeys).toEqual(["bp:user_a:shared_raw_key", "bp:user_b:shared_raw_key"]);
    // Without the namespace, both calls would send "shared_raw_key" and
    // Stripe would return user A's PaymentIntent to user B — the exact
    // cross-user leak the namespace exists to prevent.
    expect(sentKeys[0]).not.toBe(sentKeys[1]);
  });

  it("still mints a per-request key when no Idempotency-Key header is sent", async () => {
    maybeSingleMock.mockResolvedValue({ data: null, error: null });
    createPaymentIntentMock.mockResolvedValue({ id: "pi_abc", status: "succeeded" });
    supabaseInsertMock.mockResolvedValue({
      data: { id: "txn_abc", status: "completed" },
      error: null,
    });

    const POST = await loadPost();
    await POST(makeRequest({ user: "user_a" })); // no idempotencyKey

    expect(createPaymentIntentMock).toHaveBeenCalledTimes(1);
    const [, options] = createPaymentIntentMock.mock.calls[0];
    // UUID prefix is "bp:user_a:" — guards against the alternative where
    // we skipped the second-arg option entirely when the header was absent.
    expect((options as { idempotencyKey?: string }).idempotencyKey).toMatch(
      /^bp:user_a:[0-9a-f-]{36}$/i,
    );
  });
});
