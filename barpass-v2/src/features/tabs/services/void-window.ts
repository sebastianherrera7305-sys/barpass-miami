/**
 * La ventana en la que un cobro se puede anular desde la barra, y cómo se lee
 * un cobro de la lista.
 *
 * Todo puro: es la lógica que decide si el botón "Anular" existe, y esa
 * decisión no debería necesitar una base ni un reloj de servidor para
 * testearse. El servidor vuelve a chequear la ventana igual
 * (`void_window_expired` en supabase/venue_tab_void.sql) — esto es sólo para
 * no ofrecer un botón que el RPC va a rechazar.
 */

/** Ocho horas: un turno de barra. Tiene que coincidir con `c_window` del RPC. */
export const VOID_WINDOW_HOURS = 8;

/** Un cobro tal como lo devuelve GET /api/venue/tab/void. Sin member_id: la barra no sabe quién pagó. */
export type RecentCharge = {
  id: string;
  description: string;
  amount: number;
  createdAt: string;
  voidedAt: string | null;
  voidReason: string | null;
};

export type ChargeState = "voidable" | "voided" | "expired";

/** En qué estado está el cobro AHORA. `now` entra por parámetro para poder testearlo. */
export function chargeState(charge: RecentCharge, now: Date): ChargeState {
  if (charge.voidedAt) return "voided";
  const created = Date.parse(charge.createdAt);
  // Una fecha que no parsea se trata como fuera de ventana: preferimos no
  // ofrecer el botón antes que ofrecer uno que mueve plata sobre un dato roto.
  if (Number.isNaN(created)) return "expired";
  if (now.getTime() - created > VOID_WINDOW_HOURS * 3600_000) return "expired";
  return "voidable";
}

/** "hace 4 min" / "01:37". Lo que el bartender usa para reconocer SU cobro. */
export function chargeAge(charge: RecentCharge, now: Date): string {
  const created = Date.parse(charge.createdAt);
  if (Number.isNaN(created)) return "—";
  const minutes = Math.floor((now.getTime() - created) / 60_000);
  if (minutes < 1) return "recién";
  if (minutes < 60) return `hace ${minutes} min`;
  const hours = Math.floor(minutes / 60);
  return `hace ${hours} h`;
}
