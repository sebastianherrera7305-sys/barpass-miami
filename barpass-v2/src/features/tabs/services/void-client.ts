"use client";

import type { RecentCharge } from "@/features/tabs/services/void-window";

/**
 * Las dos llamadas de la pantalla de anulación. Separadas del componente
 * porque acá vive la regla que cuesta plata: el `idempotencyKey` ENTRA por
 * parámetro y nunca se genera adentro. Si esta función lo inventara, un
 * reintento después de un corte de red devolvería la plata dos veces.
 */

export type VoidOutcome =
  | { ok: true; amount: number; alreadyVoided: boolean }
  | { ok: false; code: string };

export async function fetchRecentCharges(venueId: string, secret: string): Promise<RecentCharge[]> {
  const res = await fetch(`/api/venue/tab/void?venueId=${encodeURIComponent(venueId)}`, {
    headers: { "x-venue-secret": secret },
    cache: "no-store",
  });
  const json: { charges?: RecentCharge[]; error?: string } = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(typeof json.error === "string" ? json.error : "read_failed");
  return json.charges ?? [];
}

export async function postVoid(input: {
  venueId: string;
  secret: string;
  chargeId: string;
  idempotencyKey: string;
  reason?: string;
}): Promise<VoidOutcome> {
  try {
    const res = await fetch("/api/venue/tab/void", {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-venue-secret": input.secret },
      body: JSON.stringify({
        chargeId: input.chargeId,
        venueId: input.venueId,
        idempotencyKey: input.idempotencyKey,
        ...(input.reason ? { reason: input.reason } : {}),
      }),
    });
    const json: { success?: boolean; amount?: number; alreadyVoided?: boolean; error?: string } =
      await res.json().catch(() => ({}));
    if (res.ok && json.success) {
      return { ok: true, amount: json.amount ?? 0, alreadyVoided: json.alreadyVoided === true };
    }
    return { ok: false, code: typeof json.error === "string" ? json.error : "void_failed" };
  } catch {
    // Sin respuesta: la anulación pudo haber entrado igual. El reintento reusa
    // la misma clave y el servidor devuelve la misma anulación.
    return { ok: false, code: "network_error" };
  }
}
