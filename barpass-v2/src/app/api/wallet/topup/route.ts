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

  const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);
  try {
    const intent = await stripe.paymentIntents.create({
      amount: Math.round(amount * 100),
      currency: "usd",
      payment_method: stripePaymentMethodId,
      confirm: true,
      automatic_payment_methods: { enabled: true, allow_redirects: "never" },
      metadata: { purpose: "wallet_topup", customer_id: user.id },
    });
    if (intent.status !== "succeeded") {
      return NextResponse.json(
        { error: "payment_not_succeeded", status: intent.status },
        { status: 402 },
      );
    }
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
  const { data: rpcData, error: rpcError } = await withRetry(() =>
    supabase.rpc("adjust_wallet_balance", {
      p_user_id: user.id,
      p_amount: amount,
      p_kind: "topup",
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
