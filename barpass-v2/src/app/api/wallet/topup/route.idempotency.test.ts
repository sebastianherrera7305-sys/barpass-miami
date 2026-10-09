import { describe, it, expect, vi, beforeEach } from "vitest";

// Prove /api/wallet/topup is now end-to-end idempotent: a client retry
// of the SAME top-up attempt (dropped response, double-tap) never charges
// the card twice AND never credits the wallet twice. The chain is:
//   Stripe.paymentIntents.create({...}, { idempotencyKey }) → same PI
//   back → adjust_wallet_balance RPC gets p_stripe_payment_intent_id →
//   RPC sees prior row for that PI id → returns prior transaction
//   untouched → no new credit.
// This test covers the Next.js side; the dedup inside the RPC itself is
// covered by wallet_topup_idempotency.sql's own verification block.

const createPaymentIntentMock = vi.fn();
const rpcMock = vi.fn();

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
        rpc: (name: string, args: Record<string, unknown>) =>
          (globalThis as unknown as {
            __rpc: (n: string, a: Record<string, unknown>) => Promise<unknown>;
          }).__rpc(name, args),
      },
    };
  },
}));

vi.mock("@/lib/rate-limit", () => ({ checkRateLimit: async () => true }));
vi.mock("@/lib/with-retry", () => ({ withRetry: async (fn: () => Promise<unknown>) => fn() }));

(globalThis as unknown as { __createPIM: unknown }).__createPIM = createPaymentIntentMock;
(globalThis as unknown as { __rpc: unknown }).__rpc = rpcMock;

process.env.STRIPE_SECRET_KEY = "sk_test_topup_fixture";

async function loadPost() {
  const { POST } = await import("./route");
  return POST;
}

function makeRequest(opts: {
  idempotencyKey?: string;
  user?: string;
  amount?: number;
}): Request {
  const headers: Record<string, string> = {
    "content-type": "application/json",
    "x-test-user": opts.user ?? "user_a",
  };
  if (opts.idempotencyKey) headers["idempotency-key"] = opts.idempotencyKey;
  return new Request("https://barpass.test/api/wallet/topup", {
    method: "POST",
    headers,
    body: JSON.stringify({
      amount: opts.amount ?? 25,
      stripePaymentMethodId: "pm_test_card_visa",
    }),
  });
}

describe("POST /api/wallet/topup — Stripe idempotency and RPC dedup", () => {
  beforeEach(() => {
    createPaymentIntentMock.mockReset();
    rpcMock.mockReset();
  });

  it("passes the Idempotency-Key, namespaced per user AND per :topup:, to Stripe", async () => {
    createPaymentIntentMock.mockResolvedValue({ id: "pi_topup_1", status: "succeeded" });
    rpcMock.mockResolvedValue({ data: [{ balance: 125 }], error: null });

    const POST = await loadPost();
    const res = await POST(makeRequest({ idempotencyKey: "topup_attempt_1", user: "user_a" }));
    expect(res.status).toBe(200);

    expect(createPaymentIntentMock).toHaveBeenCalledTimes(1);
    const [, options] = createPaymentIntentMock.mock.calls[0];
    // Namespaced with user id AND the :topup: scope so a user can hold
    // an open /api/transactions attempt and an open /api/wallet/topup
    // attempt with the same raw client key without them colliding at
    // Stripe.
    expect(options).toEqual({ idempotencyKey: "bp:user_a:topup:topup_attempt_1" });
  });

  it("forwards the Stripe PaymentIntent id to adjust_wallet_balance so the RPC can dedup", async () => {
    createPaymentIntentMock.mockResolvedValue({ id: "pi_topup_42", status: "succeeded" });
    rpcMock.mockResolvedValue({ data: [{ balance: 50 }], error: null });

    const POST = await loadPost();
    await POST(makeRequest({ idempotencyKey: "k_42", user: "user_a", amount: 10 }));

    expect(rpcMock).toHaveBeenCalledWith("adjust_wallet_balance", {
      p_user_id: "user_a",
      p_amount: 10,
      p_kind: "topup",
      p_stripe_payment_intent_id: "pi_topup_42",
    });
  });

  it("in a concurrent-request race, both requests send the SAME Stripe idempotency key — Stripe serializes and does NOT double-charge", async () => {
    const sentKeys: string[] = [];
    createPaymentIntentMock.mockImplementation(
      async (_params: unknown, options: { idempotencyKey?: string }) => {
        sentKeys.push(options?.idempotencyKey ?? "<MISSING>");
        return { id: "pi_race", status: "succeeded" };
      },
    );
    rpcMock.mockResolvedValue({ data: [{ balance: 20 }], error: null });

    const POST = await loadPost();
    await Promise.all([
      POST(makeRequest({ idempotencyKey: "race_topup", user: "user_a" })),
      POST(makeRequest({ idempotencyKey: "race_topup", user: "user_a" })),
    ]);

    expect(sentKeys).toEqual([
      "bp:user_a:topup:race_topup",
      "bp:user_a:topup:race_topup",
    ]);
  });

  it("in that same race, both RPC calls pass the SAME PaymentIntent id — so the RPC's UNIQUE constraint on stripe_payment_intent_id guarantees the second credit is a no-op", async () => {
    createPaymentIntentMock.mockResolvedValue({ id: "pi_race_rpc", status: "succeeded" });
    const rpcCalls: Array<Record<string, unknown>> = [];
    rpcMock.mockImplementation(async (_name: string, args: Record<string, unknown>) => {
      rpcCalls.push(args);
      return { data: [{ balance: 20 }], error: null };
    });

    const POST = await loadPost();
    await Promise.all([
      POST(makeRequest({ idempotencyKey: "k", user: "user_a" })),
      POST(makeRequest({ idempotencyKey: "k", user: "user_a" })),
    ]);

    expect(rpcCalls).toHaveLength(2);
    expect(rpcCalls[0].p_stripe_payment_intent_id).toBe("pi_race_rpc");
    expect(rpcCalls[1].p_stripe_payment_intent_id).toBe("pi_race_rpc");
    // Same PI id to both calls → the server-side UNIQUE index on
    // wallet_transactions.stripe_payment_intent_id (migration
    // wallet_topup_idempotency.sql) is what makes the SECOND one a no-op.
    // Without the forwarded PI id, both would credit — the exact bug
    // this fix exists for.
  });

  it("still mints a per-request Stripe key when no Idempotency-Key header is sent — so a stale URLSession retry can't double-charge even without a client header", async () => {
    createPaymentIntentMock.mockResolvedValue({ id: "pi_hdr_nil", status: "succeeded" });
    rpcMock.mockResolvedValue({ data: [{ balance: 100 }], error: null });

    const POST = await loadPost();
    await POST(makeRequest({ user: "user_a" }));

    expect(createPaymentIntentMock).toHaveBeenCalledTimes(1);
    const [, options] = createPaymentIntentMock.mock.calls[0];
    expect((options as { idempotencyKey?: string }).idempotencyKey).toMatch(
      /^bp:user_a:topup:[0-9a-f-]{36}$/i,
    );
  });
});
