import { NextResponse } from "next/server";
import { z } from "zod";
import { checkRateLimit } from "@/lib/rate-limit";
import { requireUser } from "@/lib/supabase/require-user";
import { requireAgeVerified21 } from "@/lib/age-verification";

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

  // The actual venue-access-granting step (both the card/order path and
  // the wallet path mint a pass here) — this is THE place to enforce 21+
  // server-side, covering every payment method at once. See
  // src/lib/age-verification.ts for why this exists at all.
  const ageDenied = await requireAgeVerified21(supabase, user.id);
  if (ageDenied) return ageDenied;

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
  // Scoped to the caller: pass_code is client-chosen and travels inside
  // shared QR/share cards, so an unscoped lookup handed anyone who had seen
  // a code the full record of someone else's pass (owner, amount, validity).
  const { data: existingPass } = await supabase
    .from("passes")
    .select()
    .eq("pass_code", passCode)
    .eq("customer_id", user.id)
    .maybeSingle();
  if (existingPass) {
    return NextResponse.json({ success: true, pass: existingPass });
  }

  // Idempotent on the PAYMENT, not just on the code (2026-09-12). The iOS
  // app now keeps a durable outbox and re-sends this request after a lost
  // response, a timeout, or a relaunch. Both `source_order_id` and
  // `source_wallet_transaction_id` are UNIQUE (pass_payment_verification.sql,
  // re-asserted in passes_idempotency_2026_09_12.sql), so if this payment
  // already backs a pass of THIS user, the only correct answer is that pass —
  // never a 409 that the client would have to show as "your paid pass
  // failed". Scoped to the caller so a leaked order id can't read someone
  // else's pass.
  const sourceColumn =
    paymentSource.type === "order" ? "source_order_id" : "source_wallet_transaction_id";
  const sourceValue =
    paymentSource.type === "order" ? paymentSource.orderId : paymentSource.walletTransactionId;
  const { data: passForPayment } = await supabase
    .from("passes")
    .select()
    .eq(sourceColumn, sourceValue)
    .eq("customer_id", user.id)
    .maybeSingle();
  if (passForPayment) {
    return NextResponse.json({ success: true, pass: passForPayment });
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

  // The payment source proves money moved; it does NOT prove the right
  // amount moved. Verified 2026-09-09: nothing compared verifiedAmount to a
  // price, and /api/wallet/spend takes any positive amount — so a $0.01
  // wallet spend minted a real, redeemable table pass (redeem checks the
  // code, venue and expiry, never the amount).
  //
  // The first version of this check refused outright when venue_pass_prices
  // had no row. That table is empty for all 1,734 venues, so it turned every
  // purchase into "card charged, pass refused" — strictly worse than the hole
  // it closed. Corrected 2026-09-11: a per-venue row still wins when one
  // exists, and otherwise the floor is the app's OWN advertised price for
  // that kind, which is a real number the product already charges, not an
  // invented one:
  //
  //   skip_line  SkipLinePassView: $25 / 1, $45 / 2, $80 / 4  → $20 per person
  //   table      TableReservation.swift deposits: $100, $200, $500 → $100
  //   event_ticket  EventTicket.swift: $20, $45, $80 → $20, unless this
  //                 venue has an event with a lower real student price.
  //
  // A floor, not an equality: tiers are cheaper per head at larger sizes and
  // a student ticket is legitimately lower, so the rule is "paid at least the
  // cheapest price this kind can legitimately cost".
  const APP_MIN_UNIT_PRICE: Record<string, number> = {
    skip_line: 20,
    table: 100,
    event_ticket: 20,
  };

  const { data: priceRow } = await supabase
    .from("venue_pass_prices")
    .select("unit_price")
    .eq("venue_id", venueId)
    .eq("kind", kind)
    .maybeSingle();

  let unitFloor = priceRow ? Number(priceRow.unit_price) : APP_MIN_UNIT_PRICE[kind];
  if (!priceRow && kind === "event_ticket") {
    // A real, sourced exception: student tickets are genuinely cheaper, and
    // that price lives in the events table.
    const { data: cheapest } = await supabase
      .from("events")
      .select("student_price_cents")
      .eq("venue_id", venueId)
      .not("student_price_cents", "is", null)
      .order("student_price_cents", { ascending: true })
      .limit(1)
      .maybeSingle();
    if (cheapest?.student_price_cents) {
      unitFloor = Math.min(unitFloor, Number(cheapest.student_price_cents) / 100);
    }
  }

  if (unitFloor != null) {
    const expectedAmount = unitFloor * quantity;
    // Half a cent of slack for float/rounding on the client's total.
    if (verifiedAmount + 0.005 < expectedAmount) {
      return NextResponse.json(
        { error: "payment_below_price", expected: expectedAmount, paid: verifiedAmount },
        { status: 402 },
      );
    }
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
      // A unique violation here means a concurrent request (a client retry
      // racing this one) won the insert. Whichever column collided, the
      // answer for the SAME user is the pass that already exists — looked
      // up by the payment source, which is the identity that matters, and
      // scoped to the caller (the old pass_code lookup here was unscoped
      // and handed back another user's pass on a code collision).
      const { data: raced } = await supabase
        .from("passes")
        .select()
        .eq(sourceColumn, sourceValue)
        .eq("customer_id", user.id)
        .maybeSingle();
      if (raced) {
        return NextResponse.json({ success: true, pass: raced });
      }
      if (insertError.message.includes("pass_code")) {
        // The code itself is taken by a different user's pass. The client
        // must mint a new code for this same payment — retrying with this
        // one can never succeed.
        return NextResponse.json({ error: "pass_code_taken" }, { status: 409 });
      }
      // The order or wallet debit already backs someone ELSE's pass —
      // this payment has already been spent, reject the reuse.
      return NextResponse.json({ error: "payment_already_used" }, { status: 409 });
    }
    return NextResponse.json(
      { error: "persist_failed", message: insertError.message },
      { status: 500 },
    );
  }

  return NextResponse.json({ success: true, pass }, { status: 201 });
}
