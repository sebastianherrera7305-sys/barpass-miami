import { NextResponse } from "next/server";
import { z } from "zod";
import { checkRateLimit } from "@/lib/rate-limit";
import { requireUser } from "@/lib/supabase/require-user";

/**
 * POST /api/passes
 * Registers a Skip the Line / event ticket / table pass server-side right
 * after purchase, so its QR code has a real record to be checked against at
 * the door (see /api/passes/redeem). Without this, a "pass" is just a
 * string in a QR image — anyone could screenshot and reuse it.
 *
 * SECURITY (Pre-Launch Audit, Phase 1 #2): this route used to trust a
 * client-supplied `amount`/`quantity` with no link to a real payment — a
 * modified client could POST directly here and mint a valid, redeemable
 * pass for free. It now requires `paymentSource` referencing either a real
 * Stripe-backed `orders` row or a real BarPass Wallet debit
 * (`wallet_transactions`, see supabase/pass_payment_verification.sql), and
 * derives `amount` from that verified source — never from the client. A
 * unique index on both reference columns guarantees the same payment can
 * never back two passes.
 */

const passRequestSchema = z.object({
  passCode: z.string().min(4),
  kind: z.enum(["skip_line", "event_ticket", "table"]),
  venueId: z.string().min(1),
  venueName: z.string().min(1),
  // Not itself a monetary field (amount is derived from paymentSource,
  // never from this) — but redemption doesn't cross-check quantity against
  // anything, and door staff see this value on /validate. Capped so a
  // client can't inflate it into a business-logic bypass (e.g. claiming
  // "20 guests" on a 2-person table deposit to socially get more people
  // in than were paid for) — this bound doesn't fully close that gap, it
  // only removes the unbounded worst case; a real fix needs quantity tied
  // to the verified order/txn the same way amount now is (tracked as a
  // follow-up, not blocking Phase 1).
  quantity: z.number().int().positive().max(20),
  validUntil: z.string().datetime(),
  paymentSource: z.discriminatedUnion("type", [
    z.object({ type: z.literal("order"), orderId: z.string().min(1) }),
    z.object({ type: z.literal("wallet"), walletTransactionId: z.string().uuid() }),
  ]),
});

export async function POST(request: Request) {
  const auth = await requireUser(request);
  if (!auth.ok) return auth.response;
  const { supabase, user } = auth;

  // 10 registros de pase por minuto y por usuario — holgado para una noche
  // real (un pase por compra), pero cierra el martilleo de este endpoint, que
  // era el único autenticado sin límite. La clave va después de getUser para
  // que sea el user id verificado y no algo que el llamante pueda falsear.
  const withinLimit = await checkRateLimit(`passes:${user.id}`, {
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

  const parsed = passRequestSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: "invalid_payload", message: parsed.error.issues[0]?.message },
      { status: 422 },
    );
  }
  const { passCode, kind, venueId, venueName, quantity, validUntil, paymentSource } = parsed.data;

  // Idempotent retry: a flaky response after the insert already succeeded
  // shouldn't be treated as an error, but it must NOT re-verify (and
  // re-consume) the payment source a second time.
  const { data: existingPass } = await supabase
    .from("passes")
    .select()
    .eq("pass_code", passCode)
    .maybeSingle();
  if (existingPass) {
    return NextResponse.json({ success: true, pass: existingPass });
  }

  // Verify the payment source server-side and derive the real amount from
  // it — the client's own claimed amount is never trusted or used.
  let verifiedAmount: number;
  let sourceOrderId: string | null = null;
  let sourceWalletTransactionId: string | null = null;

  if (paymentSource.type === "order") {
    const { data: order, error: orderError } = await supabase
      .from("orders")
      .select("id, customer_id, vendor_id, total")
      .eq("id", paymentSource.orderId)
      .maybeSingle();
    if (orderError || !order) {
      return NextResponse.json({ error: "order_not_found" }, { status: 404 });
    }
    if (order.customer_id !== user.id) {
      return NextResponse.json({ error: "order_not_yours" }, { status: 403 });
    }
    if (order.vendor_id !== venueId) {
      return NextResponse.json({ error: "order_venue_mismatch" }, { status: 422 });
    }
    verifiedAmount = Number(order.total);
    sourceOrderId = order.id;
  } else {
    const { data: txn, error: txnError } = await supabase
      .from("wallet_transactions")
      .select("id, user_id, amount, kind")
      .eq("id", paymentSource.walletTransactionId)
      .maybeSingle();
    if (txnError || !txn) {
      return NextResponse.json({ error: "wallet_transaction_not_found" }, { status: 404 });
    }
    if (txn.user_id !== user.id) {
      return NextResponse.json({ error: "wallet_transaction_not_yours" }, { status: 403 });
    }
    if (txn.kind !== "spend") {
      return NextResponse.json({ error: "wallet_transaction_not_a_spend" }, { status: 422 });
    }
    verifiedAmount = Math.abs(Number(txn.amount));
    sourceWalletTransactionId = txn.id;
  }

  const { data: pass, error: insertError } = await supabase
    .from("passes")
    .insert({
      pass_code: passCode,
      kind,
      venue_id: venueId,
      venue_name: venueName,
      customer_id: user.id,
      quantity,
      amount: verifiedAmount,
      valid_until: validUntil,
      source_order_id: sourceOrderId,
      source_wallet_transaction_id: sourceWalletTransactionId,
    })
    .select()
    .single();

  if (insertError) {
    if (insertError.code === "23505") {
      if (insertError.message.includes("pass_code")) {
        // Duplicate pass_code — client retry racing this same request.
        const { data: retryExisting } = await supabase
          .from("passes")
          .select()
          .eq("pass_code", passCode)
          .maybeSingle();
        return NextResponse.json({ success: true, pass: retryExisting });
      }
      // The order or wallet debit already backed a different pass —
      // this payment has already been spent on a pass, reject the reuse.
      return NextResponse.json({ error: "payment_already_used" }, { status: 409 });
    }
    return NextResponse.json(
      { error: "persist_failed", message: insertError.message },
      { status: 500 },
    );
  }

  return NextResponse.json({ success: true, pass }, { status: 201 });
}
