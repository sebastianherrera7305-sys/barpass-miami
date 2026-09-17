"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { MenuPicker } from "@/features/tabs/components/menu-picker";
import { OrderPanel } from "@/features/tabs/components/order-panel";
import { ChargeScanner } from "@/features/tabs/components/charge-scanner";
import { ChargeResult } from "@/features/tabs/components/charge-result";
import { VenueSetup } from "@/features/tabs/components/venue-setup";
import { RecentCharges } from "@/features/tabs/components/recent-charges";
import { fetchVenueMenu, type MenuItem } from "@/features/tabs/services/menu-client";
import {
  addLine,
  buildChargePayload,
  orderBlocker,
  orderTotal,
  round2,
  setQty,
  type OrderLine,
} from "@/features/tabs/services/bar-order";

/**
 * La pantalla de la barra: el bartender arma el pedido y recién al final
 * escanea el código del cliente.
 *
 * El orden importa. Un flujo que pide escanear primero obliga al cliente a
 * tener el teléfono abierto y desbloqueado mientras el bartender tipea, que es
 * exactamente el tiempo muerto que esto viene a eliminar. Acá el código se
 * muestra cuando el monto ya está cerrado, y dura tres minutos: alcanza de
 * sobra para un escaneo, no para que alguien lo fotografíe y lo use después.
 *
 * LA REGLA QUE NO SE AFLOJA: `idempotencyKey` se genera UNA vez por cobro
 * (`startCharge`) y se reusa en todo reintento del mismo cobro — incluso al
 * escanear un código nuevo. Una clave nueva en un reintento le cobra dos veces
 * al cliente; la misma clave le devuelve el mismo cobro. Es la diferencia
 * entre una barra con mala señal y una queja al día siguiente.
 */

type Attempt = { key: string; token: string | null; amount: number };
type Phase = "building" | "scanning" | "charging" | "ok" | "error";

const SECRET_KEY = "bp_venue_secret";
const VENUE_KEY = "bp_venue_id";

export function BarScreen() {
  // Se lee una sola vez, al montar. Este componente no se renderiza en el
  // servidor (ver app/bar/page.tsx), así que `window` existe siempre acá.
  const [venueId, setVenueId] = useState<string | null>(() =>
    window.localStorage.getItem(VENUE_KEY),
  );
  const [secret, setSecret] = useState<string | null>(() =>
    window.localStorage.getItem(SECRET_KEY),
  );

  const [menu, setMenu] = useState<MenuItem[]>([]);
  const [menuLoading, setMenuLoading] = useState(true);
  const [lines, setLines] = useState<OrderLine[]>([]);
  const [freeAmount, setFreeAmount] = useState("");
  const [freeDescription, setFreeDescription] = useState("");
  const [forceFree, setForceFree] = useState(false);

  const [attempt, setAttempt] = useState<Attempt | null>(null);
  const [phase, setPhase] = useState<Phase>("building");
  const [errorCode, setErrorCode] = useState<string>("charge_failed");
  // La lista de anulación es una pantalla aparte y no se puede abrir con un
  // cobro a medio camino: anular lo que todavía se está cobrando es la manera
  // más rápida de dejar la noche descuadrada.
  const [showRecent, setShowRecent] = useState(false);

  useEffect(() => {
    if (!venueId) return;
    let cancelled = false;
    fetchVenueMenu(venueId)
      .then((items) => {
        if (!cancelled) setMenu(items);
      })
      .catch(() => {
        if (!cancelled) setMenu([]);
      })
      .finally(() => {
        if (!cancelled) setMenuLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [venueId]);

  const freeMode = forceFree || (!menuLoading && menu.length === 0);
  const amount = useMemo(
    () =>
      freeMode ? round2(Number.parseFloat(freeAmount.replace(",", ".")) || 0) : orderTotal(lines),
    [freeMode, freeAmount, lines],
  );
  const blocker = orderBlocker(amount);

  const post = useCallback(
    async (key: string, token: string) => {
      if (!venueId || !secret) return;
      setPhase("charging");
      const payload = buildChargePayload({
        token,
        venueId,
        lines: freeMode ? [] : lines,
        idempotencyKey: key,
        freeAmount: amount,
        freeDescription,
      });
      try {
        const res = await fetch("/api/venue/tab/charge", {
          method: "POST",
          headers: { "Content-Type": "application/json", "x-venue-secret": secret },
          body: JSON.stringify(payload),
        });
        const json: { success?: boolean; error?: string } = await res.json().catch(() => ({}));
        if (res.ok && json.success) {
          setPhase("ok");
          return;
        }
        setErrorCode(typeof json.error === "string" ? json.error : "charge_failed");
        setPhase("error");
      } catch {
        // Sin respuesta: el cobro pudo haber entrado igual. El reintento usa
        // la misma clave y el servidor devuelve el cobro que ya existe.
        setErrorCode("network_error");
        setPhase("error");
      }
    },
    [venueId, secret, freeMode, lines, amount, freeDescription],
  );

  function startCharge() {
    if (blocker) return;
    setAttempt({ key: crypto.randomUUID(), token: null, amount });
    setPhase("scanning");
  }

  function onScanned(token: string) {
    if (!attempt) return;
    setAttempt({ ...attempt, token });
    void post(attempt.key, token);
  }

  function retrySameCharge() {
    if (attempt?.token) void post(attempt.key, attempt.token);
  }

  function rescanSameCharge() {
    // La clave sobrevive al código nuevo a propósito: si el cobro anterior
    // hubiera entrado sin que lo viéramos, este reintento lo devuelve en vez
    // de cobrar otra vez.
    setPhase("scanning");
  }

  const finishAndClear = useCallback(() => {
    setLines([]);
    setFreeAmount("");
    setFreeDescription("");
    setAttempt(null);
    setPhase("building");
  }, []);

  function abandonCharge() {
    setAttempt(null);
    setPhase("building");
  }

  if (!venueId || !secret) {
    return (
      <VenueSetup
        onSaved={(id, code) => {
          window.localStorage.setItem(VENUE_KEY, id);
          window.localStorage.setItem(SECRET_KEY, code);
          setVenueId(id);
          setSecret(code);
        }}
      />
    );
  }

  return (
    <main className="flex h-dvh flex-col gap-4 p-4 lg:flex-row">
      <section className="flex min-h-0 flex-1 flex-col gap-3">
        <header className="flex items-center justify-between">
          <h1 className="text-lg font-black uppercase tracking-[2px] text-white">Barra</h1>
          <div className="flex items-center gap-4">
            {menu.length > 0 && (
              <button
                onClick={() => setForceFree((v) => !v)}
                className="text-sm text-text-secondary underline"
              >
                {forceFree ? "Usar la carta" : "Monto libre"}
              </button>
            )}
            <button
              onClick={() => setShowRecent(true)}
              disabled={phase !== "building"}
              className="text-sm text-text-secondary underline disabled:opacity-40"
            >
              Últimos cobros
            </button>
            <button
              onClick={() => {
                window.localStorage.removeItem(VENUE_KEY);
                window.localStorage.removeItem(SECRET_KEY);
                setVenueId(null);
                setSecret(null);
              }}
              className="text-sm text-text-tertiary underline"
            >
              Cambiar local
            </button>
          </div>
        </header>

        {freeMode ? (
          <div className="grid flex-1 place-items-center rounded-card border border-dashed border-border-subtle p-6 text-center text-text-secondary">
            {menu.length === 0 && !menuLoading
              ? "Este local todavía no tiene la carta cargada. Cobrá por monto libre — funciona igual."
              : "Monto libre: escribí el importe en el panel del pedido."}
          </div>
        ) : (
          <MenuPicker
            items={menu}
            loading={menuLoading}
            disabled={phase !== "building"}
            onAdd={(item) =>
              setLines((prev) =>
                addLine(prev, { id: item.id, name: item.name, unitPrice: item.price }),
              )
            }
          />
        )}
      </section>

      <OrderPanel
        lines={lines}
        onQty={(id, qty) => setLines((prev) => setQty(prev, id, qty))}
        total={amount}
        blocker={blocker}
        showBlocker={freeMode ? freeAmount.trim().length > 0 : lines.length > 0}
        freeMode={freeMode}
        freeAmount={freeAmount}
        onFreeAmount={setFreeAmount}
        freeDescription={freeDescription}
        onFreeDescription={setFreeDescription}
        onCharge={startCharge}
        onClear={() => setLines([])}
        busy={phase !== "building"}
      />

      {showRecent && (
        <RecentCharges venueId={venueId} secret={secret} onClose={() => setShowRecent(false)} />
      )}
      {phase === "scanning" && attempt && (
        <ChargeScanner amount={attempt.amount} onToken={onScanned} onCancel={abandonCharge} />
      )}
      {(phase === "charging" || phase === "ok" || phase === "error") && attempt && (
        <ChargeResult
          outcome={
            phase === "charging"
              ? { k: "charging" }
              : phase === "ok"
                ? { k: "ok", amount: attempt.amount }
                : { k: "error", code: errorCode, amount: attempt.amount }
          }
          onRetry={retrySameCharge}
          onRescan={rescanSameCharge}
          onAbandon={abandonCharge}
          onDone={finishAndClear}
        />
      )}
    </main>
  );
}
