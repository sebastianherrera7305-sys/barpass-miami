import { NextResponse } from "next/server";
import { createClient as createServiceClient } from "@supabase/supabase-js";
import { z } from "zod";
import { checkRateLimit } from "@/lib/rate-limit";

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
  const authHeader = request.headers.get("authorization");
  const token = authHeader?.startsWith("Bearer ") ? authHeader.slice(7) : null;
  if (!token) {
    return NextResponse.json({ error: "not_authenticated" }, { status: 401 });
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

  // 20 gastos/minuto por usuario — cubre uso normal (carrito + priority
  // entry en la misma sesión), frena un loop de gasto automatizado.
  const withinLimit = await checkRateLimit(`wallet-spend:${userData.user.id}`, {
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
    p_user_id: userData.user.id,
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
