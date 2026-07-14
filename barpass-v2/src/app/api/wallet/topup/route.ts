import { NextResponse } from "next/server";
import Stripe from "stripe";
import { createClient as createServiceClient } from "@supabase/supabase-js";
import { z } from "zod";

/**
 * POST /api/wallet/topup
 * Charges a card via Stripe and credits the amount to the user's BarPass
 * Wallet balance. Mirrors /api/transactions' Stripe flow but writes to
 * wallet_balances (via the adjust_wallet_balance RPC) instead of orders.
 */

const topUpRequestSchema = z.object({
  amount: z.number().positive().max(1000),
  stripePaymentMethodId: z.string().min(1),
});

export async function POST(request: Request) {
  const authHeader = request.headers.get("authorization");
  const token = authHeader?.startsWith("Bearer ") ? authHeader.slice(7) : null;
  if (!token) {
    return NextResponse.json({ error: "not_authenticated" }, { status: 401 });
  }
  if (!process.env.STRIPE_SECRET_KEY) {
    return NextResponse.json({ error: "payments_not_configured" }, { status: 503 });
  }
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!supabaseUrl || !serviceRoleKey) {
    return NextResponse.json({ error: "backend_not_configured" }, { status: 503 });
  }

  const supabase = createServiceClient(supabaseUrl, serviceRoleKey);
  const { data: userData, error: userError } = await supabase.auth.getUser(token);
  if (userError || !userData?.user) {
    return NextResponse.json({ error: "not_authenticated" }, { status: 401 });
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
      metadata: { purpose: "wallet_topup", customer_id: userData.user.id },
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

  const { data: newBalance, error: rpcError } = await supabase.rpc("adjust_wallet_balance", {
    p_user_id: userData.user.id,
    p_amount: amount,
  });

  if (rpcError) {
    // Charge already succeeded — surface clearly rather than silently losing the top-up.
    return NextResponse.json(
      { error: "credit_failed", message: rpcError.message },
      { status: 500 },
    );
  }

  return NextResponse.json({ success: true, balance: newBalance });
}
