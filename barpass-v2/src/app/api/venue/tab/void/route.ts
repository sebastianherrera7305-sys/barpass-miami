import { NextResponse } from "next/server";
import { createClient as createServiceClient } from "@supabase/supabase-js";
import { z } from "zod";
import { checkRateLimit } from "@/lib/rate-limit";
import { venueSecretMatches } from "@/lib/venue-secret";
import { mapVoidError } from "@/features/tabs/services/tab-errors";
import { VOID_WINDOW_HOURS } from "@/features/tabs/services/void-window";

/**
 * El otro lado de /api/venue/tab/charge: deshacer el cobro que no iba.
 *
 * GET  → los cobros recientes de ESTE local, para que el bartender encuentre
 *        el que erró sin pedirle nada al cliente.
 * POST → anula uno.
 *
 * Los dos verbos viven en el mismo archivo porque son el mismo recurso y la
 * misma autorización: "lo que esta barra puede anular esta noche". Partirlo en
 * dos rutas duplicaría el chequeo del secreto, que es la superficie que menos
 * conviene multiplicar.
 *
 * A diferencia del cobro, acá NO hace falta el token del cliente: una
 * anulación sólo le devuelve plata. Ver la cabecera de
 * supabase/venue_tab_void.sql, decisión 2.
 *
 * Lo que la respuesta NUNCA trae, igual que en el cobro: `member_id` y el
 * saldo. El local no aprende quién pagó ni cuánta plata le queda — ni siquiera
 * en la lista, donde sería cómodo y donde convertiría la tablet de la barra en
 * un padrón de clientes.
 */

export const voidRequestSchema = z.object({
  chargeId: z.uuid(),
  venueId: z.uuid(),
  // Opcional a propósito: exigir un motivo escrito en una barra llena produce
  // "aaa" en el 90% de los casos, que es peor que un campo vacío honesto.
  reason: z.string().trim().min(1).max(200).optional(),
  idempotencyKey: z.string().min(1).max(200),
});

type VoidRow = {
  charge_id: string;
  amount: number;
  voided_at: string;
  already_voided: boolean;
};

type RecentRow = {
  id: string;
  description: string;
  amount: number;
  created_at: string;
  voided_at: string | null;
  void_reason: string | null;
};

/** Env + secreto del local. Devuelve el cliente de servicio, o la respuesta de error. */
async function authorizeVenue(request: Request, venueId: string) {
  const secret = request.headers.get("x-venue-secret");
  if (!secret) {
    return { ok: false as const, response: NextResponse.json({ error: "not_authorized" }, { status: 401 }) };
  }

  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!supabaseUrl || !serviceRoleKey) {
    return {
      ok: false as const,
      response: NextResponse.json({ error: "backend_not_configured" }, { status: 503 }),
    };
  }
  const supabase = createServiceClient(supabaseUrl, serviceRoleKey);

  const { data: venueSecret, error: venueError } = await supabase
    .from("venue_secrets")
    .select("validation_secret")
    .eq("venue_id", venueId)
    .maybeSingle();
  if (venueError || !venueSecret?.validation_secret) {
    return { ok: false as const, response: NextResponse.json({ error: "venue_not_found" }, { status: 404 }) };
  }
  if (!venueSecretMatches(secret, venueSecret.validation_secret)) {
    return { ok: false as const, response: NextResponse.json({ error: "not_authorized" }, { status: 401 }) };
  }
  return { ok: true as const, supabase };
}

export async function GET(request: Request) {
  const venueId = new URL(request.url).searchParams.get("venueId");
  if (!venueId || !z.uuid().safeParse(venueId).success) {
    return NextResponse.json({ error: "invalid_payload" }, { status: 422 });
  }

  const withinLimit = await checkRateLimit(`venue-tab-recent:${venueId}`, {
    maxRequests: 120,
    windowSeconds: 60,
  });
  if (!withinLimit) return NextResponse.json({ error: "rate_limited" }, { status: 429 });

  const auth = await authorizeVenue(request, venueId);
  if (!auth.ok) return auth.response;

  // Sólo la ventana en la que se puede anular. Mostrar cobros de anteayer sería
  // ofrecer un botón que el RPC va a rechazar.
  const since = new Date(Date.now() - VOID_WINDOW_HOURS * 3600_000).toISOString();
  const { data, error } = await auth.supabase
    .from("venue_tab_charges")
    // Lista explícita, nunca `select *`: esta tabla tiene member_id y tab_id,
    // que son exactamente lo que la barra no debe recibir.
    .select("id, description, amount, created_at, voided_at, void_reason")
    .eq("venue_id", venueId)
    .gte("created_at", since)
    .order("created_at", { ascending: false })
    .limit(50);

  if (error) {
    console.error("[venue/tab/void] recent charges read failed", {
      venueId,
      code: error.code,
      message: error.message,
    });
    return NextResponse.json({ error: "read_failed" }, { status: 500 });
  }

  return NextResponse.json({
    charges: ((data ?? []) as RecentRow[]).map((c) => ({
      id: c.id,
      description: c.description,
      amount: Number(c.amount),
      createdAt: c.created_at,
      voidedAt: c.voided_at,
      voidReason: c.void_reason,
    })),
  });
}

export async function POST(request: Request) {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }
  const parsed = voidRequestSchema.safeParse(body);
  if (!parsed.success) return NextResponse.json({ error: "invalid_payload" }, { status: 422 });
  const { chargeId, venueId, reason, idempotencyKey } = parsed.data;

  // Más bajo que el cobro (120/min) a propósito: anular es excepcional. Un
  // local que anula treinta veces por minuto no está corrigiendo un tap, y ese
  // es justo el caso que no queremos que corra libre con un secreto filtrado.
  const withinLimit = await checkRateLimit(`venue-tab-void:${venueId}`, {
    maxRequests: 30,
    windowSeconds: 60,
  });
  if (!withinLimit) return NextResponse.json({ error: "rate_limited" }, { status: 429 });

  const auth = await authorizeVenue(request, venueId);
  if (!auth.ok) return auth.response;

  const { data, error } = await auth.supabase.rpc("void_venue_tab_charge", {
    p_charge_id: chargeId,
    p_venue_id: venueId,
    p_reason: reason ?? null,
    p_idempotency_key: idempotencyKey,
  });

  if (error) {
    // Completo para nosotros, un código pelado para la tablet: el mensaje de
    // Postgres nombra tablas y constraints.
    console.error("[venue/tab/void] void_venue_tab_charge failed", {
      venueId,
      chargeId,
      idempotencyKey,
      code: error.code,
      message: error.message,
    });
    const mapped = mapVoidError(error);
    return NextResponse.json({ error: mapped.error }, { status: mapped.status });
  }

  const row = (data as VoidRow[] | null)?.[0];
  if (!row) {
    console.error("[venue/tab/void] void_venue_tab_charge returned no row", { venueId, chargeId });
    return NextResponse.json({ error: "void_failed" }, { status: 500 });
  }

  return NextResponse.json({
    success: true,
    chargeId: row.charge_id,
    amount: Number(row.amount),
    voidedAt: row.voided_at,
    // "Ya estaba anulado" no es un error, pero la barra tiene que poder decir
    // "esto ya se había devuelto" en vez de "listo, devolví la plata".
    alreadyVoided: row.already_voided,
  });
}
