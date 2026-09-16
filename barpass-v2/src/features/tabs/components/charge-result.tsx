"use client";

import { useEffect } from "react";
import { formatMoney } from "@/features/tabs/services/bar-order";
import { chargeErrorMessage } from "@/features/tabs/services/charge-messages";

/**
 * El resultado, a pantalla completa. Se lee de lejos y en dos segundos: verde
 * y el monto cobrado, o rojo y qué hacer ahora. Nada más en pantalla, porque
 * lo que sigue es atender a la persona que ya está esperando.
 */

export type ChargeOutcome =
  | { k: "charging" }
  | { k: "ok"; amount: number }
  | { k: "error"; code: string; amount: number };

export function ChargeResult({
  outcome,
  onRetry,
  onRescan,
  onAbandon,
  onDone,
}: {
  outcome: ChargeOutcome;
  onRetry: () => void;
  onRescan: () => void;
  onAbandon: () => void;
  onDone: () => void;
}) {
  const auto = outcome.k === "ok";
  useEffect(() => {
    if (!auto) return;
    const t = setTimeout(onDone, 3000);
    return () => clearTimeout(t);
  }, [auto, onDone]);

  if (outcome.k === "charging") {
    return (
      <Screen className="bg-black/95">
        <p className="text-3xl font-black text-white">Cobrando…</p>
        <p className="text-lg text-text-secondary">No cierres ni recargues la pantalla.</p>
      </Screen>
    );
  }

  if (outcome.k === "ok") {
    return (
      <Screen className="bg-success/20">
        <p className="text-7xl">✅</p>
        <p className="text-4xl font-black uppercase tracking-[2px] text-success">Cobrado</p>
        <p className="text-7xl font-black tabular-nums text-white">{formatMoney(outcome.amount)}</p>
        <button
          onClick={onDone}
          className="rounded-button bg-white/10 px-10 py-5 text-xl font-black text-white"
        >
          Siguiente
        </button>
      </Screen>
    );
  }

  const message = chargeErrorMessage(outcome.code, outcome.amount);
  return (
    <Screen className="bg-danger/20">
      <p className="text-7xl">⛔️</p>
      <p className="max-w-xl text-center text-4xl font-black text-danger">{message.title}</p>
      <p className="max-w-xl text-center text-xl text-white">{message.detail}</p>

      <div className="flex w-full max-w-md flex-col gap-3">
        {message.action === "retry" && (
          <button
            onClick={onRetry}
            className="rounded-button bg-amber-brand px-6 py-6 text-2xl font-black text-black"
          >
            Reintentar este cobro
          </button>
        )}
        {message.action === "rescan" && (
          <button
            onClick={onRescan}
            className="rounded-button bg-amber-brand px-6 py-6 text-2xl font-black text-black"
          >
            Escanear otro código
          </button>
        )}
        <button
          onClick={onAbandon}
          className="rounded-button border border-border-strong px-6 py-4 text-lg font-bold text-white"
        >
          {message.action === "retry" ? "Cobré por otro medio — cancelar" : "Cancelar el cobro"}
        </button>
      </div>

      {message.action === "retry" && (
        <p className="max-w-md text-center text-sm text-text-secondary">
          Reintentar usa el mismo comprobante: si el cobro ya había entrado, no se cobra de nuevo.
        </p>
      )}
    </Screen>
  );
}

function Screen({ children, className }: { children: React.ReactNode; className: string }) {
  return (
    <div
      className={`fixed inset-0 z-50 flex flex-col items-center justify-center gap-6 px-6 ${className}`}
    >
      {children}
    </div>
  );
}
