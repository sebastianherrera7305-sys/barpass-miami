/**
 * El pedido que el bartender arma antes de escanear, y el payload que sale de
 * él. Todo acá es puro a propósito: es la parte de la pantalla de barra donde
 * un error se paga con plata ajena, y es la única que se puede testear sin
 * cámara, sin red y sin base.
 */

/** Una línea del pedido. `unitPrice` puede ser null: la carta admite ítems sin precio impreso. */
export type OrderLine = {
  id: string;
  name: string;
  unitPrice: number | null;
  qty: number;
};

/** Lo que se guarda verbatim como recibo en `venue_tab_charges.items`. */
export type ChargeItem = { name: string; qty: number; unitPrice: number };

export type ChargePayload = {
  token: string;
  venueId: string;
  amount: number;
  description: string;
  items: ChargeItem[];
  idempotencyKey: string;
};

/** Tope duro: el CHECK de `venue_tab_charges.amount` y del token. */
export const MAX_CHARGE = 1000;

/** Redondeo a centavos. Sumar floats sin esto deja totales de $18.299999999. */
export function round2(n: number): number {
  return Math.round((n + Number.EPSILON) * 100) / 100;
}

/**
 * El total que se cobra. Un ítem sin precio suma 0 — no se inventa un precio,
 * y la pantalla avisa aparte de que esa línea no tiene importe.
 */
export function orderTotal(lines: OrderLine[]): number {
  return round2(lines.reduce((sum, l) => sum + (l.unitPrice ?? 0) * l.qty, 0));
}

/** Suma uno al ítem si ya está en el pedido; si no, lo agrega. */
export function addLine(lines: OrderLine[], item: Omit<OrderLine, "qty">): OrderLine[] {
  const existing = lines.find((l) => l.id === item.id);
  if (existing) {
    return lines.map((l) => (l.id === item.id ? { ...l, qty: l.qty + 1 } : l));
  }
  return [...lines, { ...item, qty: 1 }];
}

/** Cambia la cantidad; en 0 o menos la línea desaparece. */
export function setQty(lines: OrderLine[], id: string, qty: number): OrderLine[] {
  if (qty <= 0) return lines.filter((l) => l.id !== id);
  return lines.map((l) => (l.id === id ? { ...l, qty } : l));
}

/** Las líneas sin precio: se muestran como advertencia antes de cobrar. */
export function linesWithoutPrice(lines: OrderLine[]): OrderLine[] {
  return lines.filter((l) => l.unitPrice === null);
}

/**
 * La descripción que va al recibo del cliente. 200 es el CHECK de la columna:
 * cortar acá evita que un pedido largo vuelva como error de Postgres.
 */
export function orderDescription(lines: OrderLine[]): string {
  const text = lines.map((l) => (l.qty > 1 ? `${l.qty}× ${l.name}` : l.name)).join(", ");
  return text.length <= 200 ? text : `${text.slice(0, 197)}…`;
}

/** Por qué este pedido todavía no se puede cobrar, o null si se puede. */
export function orderBlocker(amount: number): string | null {
  if (!(amount > 0)) return "El total tiene que ser mayor a $0.";
  if (amount > MAX_CHARGE) return `El máximo por cobro es $${MAX_CHARGE}. Cobralo en dos partes.`;
  return null;
}

/**
 * El cuerpo del POST a /api/venue/tab/charge.
 *
 * `idempotencyKey` entra como parámetro y NUNCA se genera acá: si esta función
 * pudiera inventarla, un reintento produciría una clave nueva y el cliente
 * pagaría dos veces. La genera la pantalla una sola vez por cobro.
 */
export function buildChargePayload(input: {
  token: string;
  venueId: string;
  lines: OrderLine[];
  idempotencyKey: string;
  /** Monto libre, para el local que todavía no tiene carta cargada. */
  freeAmount?: number;
  freeDescription?: string;
}): ChargePayload {
  const { token, venueId, lines, idempotencyKey } = input;
  const useFree = lines.length === 0;
  const amount = useFree ? round2(input.freeAmount ?? 0) : orderTotal(lines);
  const description = useFree
    ? (input.freeDescription?.trim() || "Consumo en barra").slice(0, 200)
    : orderDescription(lines);
  const items: ChargeItem[] = useFree
    ? []
    : lines
        .filter((l): l is OrderLine & { unitPrice: number } => l.unitPrice !== null)
        .map((l) => ({ name: l.name, qty: l.qty, unitPrice: l.unitPrice }));
  return { token, venueId, amount, description, items, idempotencyKey };
}

/**
 * Lo que devuelve el lector de QR → el token.
 *
 * El teléfono muestra el token pelado, pero un QR impreso o un deep link
 * pueden envolverlo; aceptar las tres formas cuesta cuatro líneas y evita un
 * "código inválido" que en la barra parece un bug del sistema.
 */
export function parseScannedToken(raw: string): string | null {
  const value = raw.trim();
  if (!value) return null;
  if (/^[a-f0-9]{32,96}$/i.test(value)) return value;
  try {
    const url = new URL(value);
    const fromQuery = url.searchParams.get("t") ?? url.searchParams.get("token");
    if (fromQuery?.trim()) return fromQuery.trim();
  } catch {
    // no era una URL
  }
  try {
    const parsed: unknown = JSON.parse(value);
    if (parsed && typeof parsed === "object" && "token" in parsed) {
      const token = (parsed as { token: unknown }).token;
      if (typeof token === "string" && token.trim()) return token.trim();
    }
  } catch {
    // no era JSON
  }
  return value;
}

/** $18.50 → "$18.50"; $18 → "$18". Un precio redondo con ".00" se lee peor de lejos. */
export function formatMoney(amount: number): string {
  const rounded = round2(amount);
  return Number.isInteger(rounded) ? `$${rounded}` : `$${rounded.toFixed(2)}`;
}
