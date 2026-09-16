import { describe, it, expect } from "vitest";
import { chargeErrorMessage, isRetriable } from "./charge-messages";

describe("chargeErrorMessage", () => {
  it("le habla al bartender, no al programador", () => {
    for (const code of [
      "insufficient_funds",
      "token_expired",
      "token_already_used",
      "amount_above_approved_limit",
      "token_not_found",
      "tab_closed",
      "wrong_venue",
      "invalid_amount",
      "not_authorized",
      "venue_not_found",
      "rate_limited",
      "duplicate_charge",
      "backend_not_configured",
      "network_error",
      "charge_failed",
    ]) {
      const { title, detail } = chargeErrorMessage(code, 42);
      expect(title.length).toBeGreaterThan(0);
      expect(detail.length).toBeGreaterThan(0);
      // Ni el código crudo ni jerga de base de datos llegan a la pantalla.
      expect(`${title} ${detail}`).not.toContain(code);
      expect(`${title} ${detail}`.toLowerCase()).not.toMatch(/token|postgres|null|http/);
    }
  });

  it("dice qué hacer en los tres casos que más pasan en una barra", () => {
    expect(chargeErrorMessage("insufficient_funds").title).toBe("No le alcanza el saldo");
    expect(chargeErrorMessage("insufficient_funds").detail).toContain("otra forma de pago");
    expect(chargeErrorMessage("token_expired").title).toBe("El código venció");
    expect(chargeErrorMessage("token_already_used").title).toBe("Ese código ya se usó");
  });

  it("nombra el monto cuando el cliente aprobó menos de lo que cuesta", () => {
    expect(chargeErrorMessage("amount_above_approved_limit", 45).detail).toContain("$45");
    expect(chargeErrorMessage("amount_above_approved_limit", 45.5).detail).toContain("$45.50");
  });

  it("un código desconocido no rompe la pantalla", () => {
    expect(chargeErrorMessage("something_new_from_the_server").title).toBe("No se pudo cobrar");
  });
});

describe("isRetriable — qué reintento puede reusar la idempotencyKey", () => {
  it("es reintentable exactamente lo que dejó el resultado en duda", () => {
    for (const code of ["network_error", "charge_failed", "rate_limited", "duplicate_charge"]) {
      expect(isRetriable(code)).toBe(true);
    }
  });

  it("no ofrece reintentar lo que el servidor rechazó de forma definitiva", () => {
    for (const code of [
      "insufficient_funds",
      "token_expired",
      "token_already_used",
      "amount_above_approved_limit",
      "wrong_venue",
      "tab_closed",
      "not_authorized",
    ]) {
      expect(isRetriable(code)).toBe(false);
    }
  });
});
