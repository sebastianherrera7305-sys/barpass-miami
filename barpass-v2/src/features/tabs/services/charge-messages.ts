/**
 * El código de error de /api/venue/tab/charge → la frase que el bartender
 * necesita leer a un metro, con una persona esperando enfrente.
 *
 * Dos reglas que no son cosméticas:
 *  1. La frase dice QUÉ HACER, no qué falló. "token_expired" no le sirve a
 *     nadie parado en una barra; "pedile que genere otro código" sí.
 *  2. `action` decide si el reintento puede reusar la misma idempotencyKey.
 *     `retry` es para los finales AMBIGUOS (red cortada, 5xx, carrera): ahí el
 *     cobro pudo haber entrado, y reintentar con la MISMA clave devuelve el
 *     mismo cobro en vez de cobrar dos veces. `rescan` y `fix` son respuestas
 *     definitivas del servidor — no se movió un centavo.
 */

export type ChargeAction =
  | "retry" // mismo cobro, misma clave: el resultado es incierto
  | "rescan" // hace falta un código nuevo del cliente
  | "fix" // hay que corregir el pedido o la configuración del local
  | "none";

export type ChargeMessage = { title: string; detail: string; action: ChargeAction };

/** `$18.50` para meter dentro de una frase. */
function money(amount: number | undefined): string {
  if (amount === undefined) return "este monto";
  return Number.isInteger(amount) ? `$${amount}` : `$${amount.toFixed(2)}`;
}

/**
 * @param code el `error` del JSON de la ruta, o `network_error` si no hubo respuesta.
 * @param amount el total que se intentó cobrar, para las frases que lo nombran.
 */
export function chargeErrorMessage(code: string, amount?: number): ChargeMessage {
  switch (code) {
    case "insufficient_funds":
      return {
        title: "No le alcanza el saldo",
        detail: "Pedile otra forma de pago, o que cargue saldo y volvé a escanear.",
        action: "rescan",
      };
    case "token_expired":
      return {
        title: "El código venció",
        detail: "Los códigos duran tres minutos. Pedile que genere otro y escaneá de nuevo.",
        action: "rescan",
      };
    case "token_already_used":
      return {
        title: "Ese código ya se usó",
        detail: "Cada código sirve para un solo cobro. Pedile uno nuevo.",
        action: "rescan",
      };
    case "amount_above_approved_limit":
      return {
        title: "Aprobó menos de lo que cuesta",
        detail: `El código autoriza menos de ${money(amount)}. Pedile un código nuevo por ${money(amount)}.`,
        action: "rescan",
      };
    case "token_not_found":
      return {
        title: "Código inválido",
        detail: "No es un código de BarPass, o ya no existe. Pedile que lo genere de nuevo.",
        action: "rescan",
      };
    case "tab_closed":
      return {
        title: "Cerró su cuenta",
        detail: "Tiene que volver a abrirla en la app y mostrarte un código nuevo.",
        action: "rescan",
      };
    case "wrong_venue":
      return {
        title: "Ese código es de otro local",
        detail: "Abrió la cuenta en otro lugar. Pedile que abra una acá y genere el código.",
        action: "rescan",
      };
    case "invalid_amount":
    case "invalid_payload":
    case "invalid_json":
      return {
        title: "El monto no es válido",
        detail: "Revisá el pedido: el total tiene que ser mayor a $0 y menor a $1000.",
        action: "fix",
      };
    case "not_authorized":
      return {
        title: "El código del local no sirve",
        detail: "Tocá “Cambiar local” y cargá de nuevo el ID y el código que te dio BarPass.",
        action: "fix",
      };
    case "venue_not_found":
      return {
        title: "Local no encontrado",
        detail: "El ID del local no existe. Tocá “Cambiar local” y verificá el ID.",
        action: "fix",
      };
    case "rate_limited":
      return {
        title: "Demasiados cobros seguidos",
        detail: "Esperá unos segundos y tocá Reintentar. El cobro no se duplica.",
        action: "retry",
      };
    case "duplicate_charge":
      return {
        title: "Este cobro ya estaba entrando",
        detail: "Tocá Reintentar para confirmar el resultado. No se cobra dos veces.",
        action: "retry",
      };
    case "backend_not_configured":
      return {
        title: "El sistema no está configurado",
        detail: "Avisá a BarPass. No se puede cobrar por la app hasta que lo resuelvan.",
        action: "fix",
      };
    case "network_error":
      return {
        title: "Se cortó la conexión",
        detail: "Puede que el cobro haya entrado igual. Tocá Reintentar: si ya entró, no se cobra de nuevo.",
        action: "retry",
      };
    case "charge_failed":
    default:
      return {
        title: "No se pudo cobrar",
        detail: "Tocá Reintentar. Si vuelve a fallar, cobrá por otro medio y avisá a BarPass.",
        action: "retry",
      };
  }
}

/** Verdadero cuando el resultado fue ambiguo y el reintento DEBE reusar la clave. */
export function isRetriable(code: string): boolean {
  return chargeErrorMessage(code).action === "retry";
}
