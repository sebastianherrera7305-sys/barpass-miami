import { describe, it, expect } from "vitest";
import { chargeAge, chargeState, VOID_WINDOW_HOURS, type RecentCharge } from "./void-window";
import { voidErrorMessage } from "./charge-messages";
import { mapVoidError } from "./tab-errors";
import { voidRequestSchema } from "@/app/api/venue/tab/void/route";

const NOW = new Date("2026-09-17T04:00:00.000Z");

function charge(over: Partial<RecentCharge> = {}): RecentCharge {
  return {
    id: "11111111-1111-4111-8111-111111111111",
    description: "2× Margarita",
    amount: 28,
    createdAt: "2026-09-17T03:50:00.000Z",
    voidedAt: null,
    voidReason: null,
    ...over,
  };
}

describe("chargeState", () => {
  it("un cobro recién hecho se puede anular", () => {
    expect(chargeState(charge(), NOW)).toBe("voidable");
  });

  it("un cobro ya anulado no ofrece el botón, aunque esté en ventana", () => {
    expect(chargeState(charge({ voidedAt: "2026-09-17T03:55:00.000Z" }), NOW)).toBe("voided");
  });

  it("justo en el borde de la ventana todavía se puede anular", () => {
    const edge = new Date(NOW.getTime() - VOID_WINDOW_HOURS * 3600_000).toISOString();
    expect(chargeState(charge({ createdAt: edge }), NOW)).toBe("voidable");
  });

  it("un segundo después del borde, no", () => {
    const past = new Date(NOW.getTime() - VOID_WINDOW_HOURS * 3600_000 - 1000).toISOString();
    expect(chargeState(charge({ createdAt: past }), NOW)).toBe("expired");
  });

  it("una fecha rota se trata como fuera de ventana, no como anulable", () => {
    expect(chargeState(charge({ createdAt: "no es una fecha" }), NOW)).toBe("expired");
  });

  it("anulado gana sobre vencido: se muestra tachado, no como caducado", () => {
    const past = new Date(NOW.getTime() - 20 * 3600_000).toISOString();
    expect(chargeState(charge({ createdAt: past, voidedAt: past }), NOW)).toBe("voided");
  });
});

describe("chargeAge", () => {
  it("dice lo que el bartender usa para reconocer su cobro", () => {
    expect(chargeAge(charge({ createdAt: NOW.toISOString() }), NOW)).toBe("recién");
    expect(chargeAge(charge({ createdAt: "2026-09-17T03:50:00.000Z" }), NOW)).toBe("hace 10 min");
    expect(chargeAge(charge({ createdAt: "2026-09-17T01:30:00.000Z" }), NOW)).toBe("hace 2 h");
    expect(chargeAge(charge({ createdAt: "ayer" }), NOW)).toBe("—");
  });
});

describe("mapVoidError", () => {
  const pg = (message: string) => ({ message, code: "P0001" });

  it("mapea cada falla documentada a su código estable", () => {
    const cases: Array<[string, string, number]> = [
      ["charge_not_found", "charge_not_found", 404],
      ["wrong_venue", "wrong_venue", 403],
      ["void_window_expired", "void_window_expired", 410],
      ["invalid_idempotency_key", "invalid_idempotency_key", 422],
      ["insufficient_funds", "insufficient_funds", 402],
    ];
    for (const [raised, error, status] of cases) {
      expect(mapVoidError(pg(raised))).toEqual({ error, status });
    }
  });

  it("nunca deja pasar el mensaje de Postgres", () => {
    const mapped = mapVoidError(
      pg('null value in column "void_wallet_transaction_id" of relation "venue_tab_charges"'),
    );
    expect(mapped).toEqual({ error: "void_failed", status: 500 });
  });

  it("una anulación repetida no es un error: el RPC la devuelve como éxito", () => {
    // `already_voided` viaja en el cuerpo de una 200, así que jamás debe
    // aparecer en la tabla de errores.
    expect(mapVoidError(pg("already_voided"))).toEqual({ error: "void_failed", status: 500 });
  });
});

describe("voidErrorMessage", () => {
  it("sólo los finales ambiguos ofrecen reintentar", () => {
    expect(voidErrorMessage("network_error").action).toBe("retry");
    expect(voidErrorMessage("rate_limited").action).toBe("retry");
    expect(voidErrorMessage("void_failed").action).toBe("retry");
    // Estos son respuestas definitivas del servidor: no se movió un centavo y
    // reintentar sólo haría perder tiempo con una persona esperando enfrente.
    expect(voidErrorMessage("void_window_expired").action).toBe("close");
    expect(voidErrorMessage("charge_not_found").action).toBe("close");
    expect(voidErrorMessage("wrong_venue").action).toBe("close");
    expect(voidErrorMessage("not_authorized").action).toBe("close");
  });

  it("un código desconocido no rompe la pantalla", () => {
    const message = voidErrorMessage("algo_que_no_existe");
    expect(message.title).toBe("No se pudo anular");
    expect(message.action).toBe("retry");
  });
});

describe("voidRequestSchema", () => {
  const base = {
    chargeId: "11111111-1111-4111-8111-111111111111",
    venueId: "22222222-2222-4222-8222-222222222222",
    idempotencyKey: "key-1",
  };

  it("acepta el cuerpo mínimo, sin motivo", () => {
    expect(voidRequestSchema.safeParse(base).success).toBe(true);
  });

  it("exige la clave de idempotencia: sin ella se podría devolver dos veces", () => {
    expect(voidRequestSchema.safeParse({ ...base, idempotencyKey: "" }).success).toBe(false);
    expect(voidRequestSchema.safeParse({ chargeId: base.chargeId, venueId: base.venueId }).success)
      .toBe(false);
  });

  it("rechaza ids que no son uuid y motivos más largos que la columna", () => {
    expect(voidRequestSchema.safeParse({ ...base, chargeId: "42" }).success).toBe(false);
    expect(voidRequestSchema.safeParse({ ...base, venueId: "42" }).success).toBe(false);
    expect(voidRequestSchema.safeParse({ ...base, reason: "x".repeat(201) }).success).toBe(false);
  });
});
