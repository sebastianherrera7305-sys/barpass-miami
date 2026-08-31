import { NextResponse } from "next/server";
import { z } from "zod";
import { checkRateLimit } from "@/lib/rate-limit";
import { requireUser } from "@/lib/supabase/require-user";

/**
 * POST /api/wallet/spend
 * Debits the user's BarPass Wallet balance (Skip the Line, tickets, table
 * deposits, cart checkout paid "with wallet"). No Stripe call — this is an
 * internal balance transfer against money already collected at top-up time.
 * Atomic via adjust_wallet_balance; never lets balance go negative.
 */

export const spendRequestSchema = z.object({
  amount: z.number().positive(),
});

export async function POST(request: Request) {
  const auth = await requireUser(request);
  if (!auth.ok) return auth.response;
  const { supabase, user } = auth;

  // 20 gastos/minuto por usuario — cubre uso normal (carrito + priority
  // entry en la misma sesión), frena un loop de gasto automatizado.
  const withinLimit = await checkRateLimit(`wallet-spend:${user.id}`, {
    maxRequests: 20,
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
  const parsed = spendRequestSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: "invalid_payload" }, { status: 422 });
  }

  const { data: rpcData, error: rpcError } = await supabase.rpc("adjust_wallet_balance", {
    p_user_id: user.id,
    p_amount: -parsed.data.amount,
    p_kind: "spend",
  });

  if (rpcError || !rpcData?.[0]) {
    if (rpcError?.message.includes("insufficient_funds")) {
      return NextResponse.json({ error: "insufficient_funds" }, { status: 402 });
    }
    return NextResponse.json({ error: "debit_failed", message: rpcError?.message }, { status: 500 });
  }

  // transactionId is the server-side proof this specific debit happened —
  // POST /api/passes requires it to mint a pass, so a client can no longer
  // create a valid pass without a matching, unreused wallet debit.
  return NextResponse.json({
    success: true,
    balance: rpcData[0].balance,
    transactionId: rpcData[0].transaction_id,
  });
}
