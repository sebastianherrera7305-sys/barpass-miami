import { describe, it, expect } from "vitest";
import {
  addLine,
  buildChargePayload,
  formatMoney,
  linesWithoutPrice,
  orderBlocker,
  orderDescription,
  orderTotal,
  parseScannedToken,
  setQty,
  type OrderLine,
} from "./bar-order";

const line = (over: Partial<OrderLine> = {}): OrderLine => ({
  id: "1",
  name: "Old Fashioned",
  unitPrice: 18,
  qty: 1,
  ...over,
});

describe("orderTotal", () => {
  it("suma precio × cantidad", () => {
    expect(orderTotal([line({ qty: 2 }), line({ id: "2", name: "Corona", unitPrice: 9, qty: 3 })])).toBe(63);
  });

  it("no arrastra el error de coma flotante", () => {
    const lines = [
      line({ id: "a", unitPrice: 0.1, qty: 1 }),
      line({ id: "b", unitPrice: 0.2, qty: 1 }),
    ];
    expect(orderTotal(lines)).toBe(0.3);
  });

  it("cuenta como $0 el ítem sin precio en vez de inventarle uno", () => {
    expect(orderTotal([line({ unitPrice: null, qty: 4 })])).toBe(0);
    expect(linesWithoutPrice([line({ unitPrice: null })])).toHaveLength(1);
  });

  it("un pedido vacío es $0", () => {
    expect(orderTotal([])).toBe(0);
  });
});

describe("addLine / setQty", () => {
  it("un segundo tap del mismo trago suma cantidad, no una línea nueva", () => {
    const once = addLine([], { id: "1", name: "Corona", unitPrice: 9 });
    const twice = addLine(once, { id: "1", name: "Corona", unitPrice: 9 });
    expect(twice).toHaveLength(1);
    expect(twice[0].qty).toBe(2);
  });

  it("bajar a cero saca la línea del pedido", () => {
    expect(setQty([line()], "1", 0)).toEqual([]);
    expect(setQty([line()], "1", 3)[0].qty).toBe(3);
  });
});

describe("orderDescription", () => {
  it("escribe el recibo en el idioma de la barra", () => {
    expect(orderDescription([line({ qty: 2 }), line({ id: "2", name: "Corona", unitPrice: 9 })])).toBe(
      "2× Old Fashioned, Corona",
    );
  });

  it("corta en el límite de la columna (200) en vez de dejar que falle Postgres", () => {
    const many = Array.from({ length: 40 }, (_, i) => line({ id: String(i), name: `Trago ${i}` }));
    const text = orderDescription(many);
    expect(text.length).toBeLessThanOrEqual(200);
    expect(text.endsWith("…")).toBe(true);
  });
});

describe("orderBlocker", () => {
  it("no deja cobrar $0 ni un monto negativo", () => {
    expect(orderBlocker(0)).not.toBeNull();
    expect(orderBlocker(-1)).not.toBeNull();
  });

  it("no deja cobrar por encima del CHECK de la base", () => {
    expect(orderBlocker(1000)).toBeNull();
    expect(orderBlocker(1000.01)).not.toBeNull();
  });
});

describe("buildChargePayload", () => {
  const base = {
    token: "a".repeat(48),
    venueId: "8f2b1c3d-4e5f-4a6b-8c9d-0e1f2a3b4c5d",
    idempotencyKey: "key-1",
  };

  it("arma el cuerpo exacto que espera /api/venue/tab/charge", () => {
    const payload = buildChargePayload({
      ...base,
      lines: [line({ qty: 2 }), line({ id: "2", name: "Corona", unitPrice: 9 })],
    });
    expect(payload).toEqual({
      token: base.token,
      venueId: base.venueId,
      amount: 45,
      description: "2× Old Fashioned, Corona",
      items: [
        { name: "Old Fashioned", qty: 2, unitPrice: 18 },
        { name: "Corona", qty: 1, unitPrice: 9 },
      ],
      idempotencyKey: "key-1",
    });
  });

  it("usa la clave que le dan, siempre — reintentar no puede generar una nueva", () => {
    const first = buildChargePayload({ ...base, lines: [line()] });
    const retry = buildChargePayload({ ...base, lines: [line()] });
    expect(retry.idempotencyKey).toBe(first.idempotencyKey);
  });

  it("no manda al recibo un ítem sin precio", () => {
    const payload = buildChargePayload({ ...base, lines: [line(), line({ id: "2", unitPrice: null })] });
    expect(payload.items).toHaveLength(1);
  });

  it("sin carta cargada cobra el monto libre con su descripción", () => {
    const payload = buildChargePayload({
      ...base,
      lines: [],
      freeAmount: 24.5,
      freeDescription: "  2 cervezas  ",
    });
    expect(payload.amount).toBe(24.5);
    expect(payload.description).toBe("2 cervezas");
    expect(payload.items).toEqual([]);
  });

  it("una descripción libre vacía no queda vacía: la columna exige al menos un carácter", () => {
    const payload = buildChargePayload({ ...base, lines: [], freeAmount: 10, freeDescription: "   " });
    expect(payload.description).toBe("Consumo en barra");
  });
});

describe("parseScannedToken", () => {
  it("acepta el token pelado", () => {
    const token = "b".repeat(48);
    expect(parseScannedToken(token)).toBe(token);
    expect(parseScannedToken(` ${token} `)).toBe(token);
  });

  it("lo desenvuelve de una URL o de un JSON", () => {
    expect(parseScannedToken("https://barpass.app/t?t=abc123")).toBe("abc123");
    expect(parseScannedToken('{"token":"abc123"}')).toBe("abc123");
  });

  it("no devuelve un token vacío", () => {
    expect(parseScannedToken("   ")).toBeNull();
  });
});

describe("formatMoney", () => {
  it("no muestra centavos que no existen", () => {
    expect(formatMoney(18)).toBe("$18");
    expect(formatMoney(18.5)).toBe("$18.50");
  });
});
