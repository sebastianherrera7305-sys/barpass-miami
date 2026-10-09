import { NextResponse } from "next/server";
import Stripe from "stripe";
import { z } from "zod";
import { checkRateLimit } from "@/lib/rate-limit";
import { requireUser } from "@/lib/supabase/require-user";
import { withRetry } from "@/lib/with-retry";

/**
 * POST /api/wallet/topup
 * Charges a card via Stripe and credits the amount to the user's BarPass
 * Wallet balance. Mirrors /api/transactions' Stripe flow but writes to
 * wallet_balances (via the adjust_wallet_balance RPC) instead of orders.
 */

export const topUpRequestSchema = z.object({
  amount: z.number().positive().max(1000),
  stripePaymentMethodId: z.string().min(1),
});

export async function POST(request: Request) {
  const auth = await requireUser(request);
  if (!auth.ok) return auth.response;
  const { supabase, user } = auth;

  if (!process.env.STRIPE_SECRET_KEY) {
    return NextResponse.json({ error: "payments_not_configured" }, { status: 503 });
  }

  // 10 top-ups/minuto por usuario — deja pasar reintentos legítimos de
  // tarjeta rechazada, frena card-testing/carding.
  const withinLimit = await checkRateLimit(`wallet-topup:${user.id}`, {
    maxRequests: 10,
    windowSeconds: 60,
  });
  if (!withinLimit) {
    return NextResponse.json({ error: "rate_limited" }, { status: 429 });
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }
  const parsed = topUpRequestSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: "invalid_payload", message: parsed.error.issues[0]?.message },
      { status: 422 },
    );
  }
  const { amount, stripePaymentMethodId } = parsed.data;

  // Same idempotency discipline as /api/transactions. The client header
  // (set by iOS APIClient.topUpWallet) is namespaced by user.id before
  // handing it to Stripe — see the long comment in
  // src/app/api/transactions/route.ts for the full reasoning.
  //
  // Unlike /api/transactions, this route has no DB pre-check table to
  // short-circuit a prior successful credit. Instead, the wallet-side
  // guard lives inside the adjust_wallet_balance RPC: it takes the
  // Stripe PaymentIntent id as its 4th arg, and wallet_transactions has
  // a UNIQUE index on stripe_payment_intent_id. The RPC checks for a
  // prior row with that PI id and returns the existing transaction
  // untouched if found — no new credit, no new ledger row.
  //
  // So the full chain for a retry (dropped response, re-tap, URLSession
  // retry) is: Stripe returns the SAME PaymentIntent (idempotencyKey),
  // the route calls the RPC with that PI id, the RPC sees it already
  // credited the wallet and no-ops. Neither Stripe charges twice nor
  // does the wallet credit twice. See supabase/wallet_topup_idempotency.sql.
  const idempotencyKey = request.headers.get("idempotency-key");
  const stripeIdempotencyKey = idempotencyKey
    ? `bp:${user.id}:topup:${idempotencyKey}`
    : `bp:${user.id}:topup:${crypto.randomUUID()}`;

  const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);
  let paymentIntentId: string;
  try {
    const intent = await stripe.paymentIntents.create(
      {
        amount: Math.round(amount * 100),
        currency: "usd",
        payment_method: stripePaymentMethodId,
        confirm: true,
        automatic_payment_methods: { enabled: true, allow_redirects: "never" },
        metadata: {
          purpose: "wallet_topup",
          customer_id: user.id,
          idempotency_key: idempotencyKey ?? "",
        },
      },
      { idempotencyKey: stripeIdempotencyKey },
    );
    if (intent.status !== "succeeded") {
      return NextResponse.json(
        { error: "payment_not_succeeded", status: intent.status },
        { status: 402 },
      );
    }
    paymentIntentId = intent.id;
  } catch (err) {
    const stripeErr = err as Stripe.errors.StripeError;
    if (stripeErr.type === "StripeCardError") {
      return NextResponse.json({ error: "card_declined", message: stripeErr.message }, { status: 402 });
    }
    return NextResponse.json({ error: "stripe_error", message: stripeErr.message }, { status: 500 });
  }

  // Charge already succeeded at Stripe — retry the credit a few times
  // before giving up, so a transient Supabase blip doesn't turn a good
  // charge into an uncredited one. See src/lib/with-retry.ts.
  //
  // Passing the Stripe PaymentIntent id is what makes the RPC itself
  // idempotent (see wallet_topup_idempotency.sql). The second call for
  // the same PI id returns the prior ledger row untouched.
  const { data: rpcData, error: rpcError } = await withRetry(() =>
    supabase.rpc("adjust_wallet_balance", {
      p_user_id: user.id,
      p_amount: amount,
      p_kind: "topup",
      p_stripe_payment_intent_id: paymentIntentId,
    }),
  );

  if (rpcError || !rpcData?.[0]) {
    // Charge already succeeded — surface clearly rather than silently losing the top-up.
    return NextResponse.json(
      { error: "credit_failed", message: rpcError?.message },
      { status: 500 },
    );
  }

  return NextResponse.json({ success: true, balance: rpcData[0].balance });
}
