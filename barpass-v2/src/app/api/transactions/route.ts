import { NextResponse } from "next/server";
import Stripe from "stripe";
import { z } from "zod";
import { checkRateLimit } from "@/lib/rate-limit";
import { requireUser } from "@/lib/supabase/require-user";

/**
 * POST /api/transactions
 * Charges a card (or Apple Pay) order via Stripe and persists it to Supabase.
 * `stripePaymentMethodId` must come from a client-side Stripe tokenization
 * call — raw card data never reaches this route. Mirrors the contract the
 * iOS app already speaks (see BarPass-iOS/Core/Networking/APIClient.swift).
 */

const TAX_RATE = 0.07; // Florida

// TODO(pricing): there is no products/menu table yet — `unitPrice` is
// whatever the client sends, so a modified client can charge itself $0.01
// for anything. Real fix is a server-side price catalog to validate
// productId -> price against. Until that exists, these bounds are a stopgap
// that blocks the obvious abuse case (near-zero or wildly inflated prices)
// without blocking legitimate orders.
const MIN_UNIT_PRICE = 0.5;
const MAX_UNIT_PRICE = 5000;

export const itemSchema = z.object({
  productId: z.string().min(1),
  name: z.string().min(1),
  qty: z.number().positive().max(50),
  unitPrice: z.number().min(MIN_UNIT_PRICE).max(MAX_UNIT_PRICE),
});

export const transactionRequestSchema = z.object({
  vendorId: z.string().min(1),
  staffId: z.string().min(1),
  items: z.array(itemSchema).min(1),
  paymentMethod: z.enum(["card", "apple_pay"]),
  stripePaymentMethodId: z.string().min(1),
});

export async function POST(request: Request) {
  const auth = await requireUser(request);
  if (!auth.ok) return auth.response;
  const { supabase, user } = auth;

  if (!process.env.STRIPE_SECRET_KEY) {
    return NextResponse.json({ error: "payments_not_configured" }, { status: 503 });
  }

  // 10 compras/minuto por usuario — cubre una noche normal de pedidos,
  // frena card-testing/carding contra este endpoint.
  const withinLimit = await checkRateLimit(`transactions:${user.id}`, {
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

  const parsed = transactionRequestSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: "invalid_payload", message: parsed.error.issues[0]?.message },
      { status: 422 },
    );
  }
  const { vendorId, staffId, items, paymentMethod, stripePaymentMethodId } = parsed.data;

  // Idempotency — replay-safe on client retries (flaky network, double tap)
  const idempotencyKey = request.headers.get("idempotency-key");
  if (idempotencyKey) {
    const { data: existing } = await supabase
      .from("orders")
      .select("*")
      .eq("idempotency_key", idempotencyKey)
      .maybeSingle();
    if (existing) {
      return NextResponse.json({ success: true, transaction: existing });
    }
  }

  const subtotal = Math.round(items.reduce((s, i) => s + i.qty * i.unitPrice, 0) * 100) / 100;
  const tax = Math.round(subtotal * TAX_RATE * 100) / 100;
  const total = Math.round((subtotal + tax) * 100) / 100;

  const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);

  let paymentIntentId: string;
  try {
    const intent = await stripe.paymentIntents.create({
      amount: Math.round(total * 100),
      currency: "usd",
      payment_method: stripePaymentMethodId,
      confirm: true,
      automatic_payment_methods: { enabled: true, allow_redirects: "never" },
      metadata: {
        vendor_id: vendorId,
        staff_id: staffId,
        customer_id: user.id,
        idempotency_key: idempotencyKey ?? "",
      },
    });
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
      return NextResponse.json(
        { error: "card_declined", message: stripeErr.message },
        { status: 402 },
      );
    }
    return NextResponse.json(
      { error: "stripe_error", message: stripeErr.message },
      { status: 500 },
    );
  }

  const id = `txn_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
  const { data: order, error: insertError } = await supabase
    .from("orders")
    .insert({
      id,
      idempotency_key: idempotencyKey,
      vendor_id: vendorId,
      customer_id: user.id,
      items,
      subtotal,
      tax,
      total,
      payment_method: paymentMethod,
      stripe_payment_intent_id: paymentIntentId,
      status: "completed",
    })
    .select()
    .single();

  if (insertError) {
    // Charge already succeeded at Stripe — surface clearly rather than silently losing the order.
    return NextResponse.json(
      { error: "persist_failed", message: insertError.message, stripePaymentIntentId: paymentIntentId },
      { status: 500 },
    );
  }

  return NextResponse.json({ success: true, transaction: order }, { status: 201 });
}
