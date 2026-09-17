"use client";

import { useCallback, useEffect, useState } from "react";
import { formatMoney } from "@/features/tabs/services/bar-order";
import { voidErrorMessage } from "@/features/tabs/services/charge-messages";
import { fetchRecentCharges, postVoid } from "@/features/tabs/services/void-client";
import {
  chargeAge,
  chargeState,
  VOID_WINDOW_HOURS,
  type RecentCharge,
} from "@/features/tabs/services/void-window";

/**
 * Los últimos cobros de la noche en ESTE local, con un botón para anular el
 * que no iba.
 *
 * LA REGLA DE LA PANTALLA: anular NUNCA es un toque. "Anular" abre la
 * confirmación, y recién el segundo botón —que dice el monto— mueve plata. Un
 * bartender apurado pasa el dedo por la lista; no puede devolverle $40 a
 * alguien por rozar la pantalla. Y el botón de confirmar es rojo y está solo,
 * lejos de donde estaba el primero.
 *
 * La clave de idempotencia se genera UNA vez, al confirmar, y sobrevive a todo
 * reintento: si se corta la red justo después de anular, reintentar devuelve
 * la misma anulación en vez de devolver la plata dos veces.
 */

type Pending = { chargeId: string; key: string; amount: number } | null;

export function RecentCharges({
  venueId,
  secret,
  onClose,
}: {
  venueId: string;
  secret: string;
  onClose: () => void;
}) {
  const [charges, setCharges] = useState<RecentCharge[]>([]);
  const [loading, setLoading] = useState(true);
  const [listError, setListError] = useState<string | null>(null);
  const [confirming, setConfirming] = useState<string | null>(null);
  const [pending, setPending] = useState<Pending>(null);
  const [busy, setBusy] = useState(false);
  const [errorCode, setErrorCode] = useState<string | null>(null);
  const [done, setDone] = useState<{ amount: number; alreadyVoided: boolean } | null>(null);
  const now = new Date();

  // `reloads` es el disparador: cada recarga (al abrir, y después de cada
  // anulación) es un incremento, y el efecto es el único que toca el estado.
  // Llamar setState en el cuerpo del efecto encadena renders de más.
  const [reloads, setReloads] = useState(0);
  const load = useCallback(() => setReloads((n) => n + 1), []);

  useEffect(() => {
    let cancelled = false;
    fetchRecentCharges(venueId, secret)
      .then((rows) => {
        if (cancelled) return;
        setCharges(rows);
        setListError(null);
      })
      .catch((e: unknown) => {
        if (!cancelled) setListError(e instanceof Error ? e.message : "read_failed");
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [venueId, secret, reloads]);

  const run = useCallback(
    async (attempt: NonNullable<Pending>) => {
      setBusy(true);
      setErrorCode(null);
      const outcome = await postVoid({
        venueId,
        secret,
        chargeId: attempt.chargeId,
        idempotencyKey: attempt.key,
      });
      setBusy(false);
      if (outcome.ok) {
        setPending(null);
        setConfirming(null);
        setDone({ amount: outcome.amount || attempt.amount, alreadyVoided: outcome.alreadyVoided });
        load();
        return;
      }
      setErrorCode(outcome.code);
    },
    [venueId, secret, load],
  );

  function confirm(charge: RecentCharge) {
    // Una sola vez por anulación. Ver la cabecera.
    const attempt = { chargeId: charge.id, key: crypto.randomUUID(), amount: charge.amount };
    setPending(attempt);
    void run(attempt);
  }

  return (
    <div className="fixed inset-0 z-50 flex flex-col bg-black/95">
      <header className="flex items-center justify-between border-b border-border-subtle p-4">
        <div>
          <h2 className="text-lg font-black uppercase tracking-[2px] text-white">Últimos cobros</h2>
          <p className="text-sm text-text-secondary">
            De este local, de las últimas {VOID_WINDOW_HOURS} horas.
          </p>
        </div>
        <button
          onClick={onClose}
          className="rounded-button border border-border-strong px-6 py-3 text-lg font-bold text-white"
        >
          Volver a cobrar
        </button>
      </header>

      <div className="min-h-0 flex-1 overflow-y-auto p-4">
        {loading && <p className="p-6 text-center text-text-secondary">Cargando…</p>}
        {listError && !loading && (
          <div className="p-6 text-center">
            <p className="text-lg text-danger">{voidErrorMessage(listError).title}</p>
            <button onClick={load} className="mt-3 text-white underline">
              Reintentar
            </button>
          </div>
        )}
        {!loading && !listError && charges.length === 0 && (
          <p className="p-6 text-center text-text-secondary">
            Todavía no hay cobros esta noche.
          </p>
        )}

        <ul className="flex flex-col gap-2">
          {charges.map((charge) => {
            const state = chargeState(charge, now);
            return (
              <li
                key={charge.id}
                className="rounded-card border border-border-subtle p-4"
                data-state={state}
              >
                <div className="flex items-center justify-between gap-4">
                  <div className="min-w-0">
                    <p
                      className={`truncate text-lg font-bold ${
                        state === "voided" ? "text-text-tertiary line-through" : "text-white"
                      }`}
                    >
                      {charge.description}
                    </p>
                    <p className="text-sm text-text-secondary">{chargeAge(charge, now)}</p>
                  </div>
                  <p
                    className={`shrink-0 text-2xl font-black tabular-nums ${
                      state === "voided" ? "text-text-tertiary line-through" : "text-white"
                    }`}
                  >
                    {formatMoney(charge.amount)}
                  </p>
                </div>

                {state === "voided" && (
                  <p className="mt-2 text-sm font-bold uppercase tracking-[1px] text-success">
                    Anulado — se le devolvió la plata
                  </p>
                )}
                {state === "expired" && (
                  <p className="mt-2 text-sm text-text-tertiary">
                    Fuera de la ventana para anular. Avisá a BarPass.
                  </p>
                )}
                {state === "voidable" && confirming !== charge.id && (
                  <button
                    onClick={() => setConfirming(charge.id)}
                    className="mt-3 rounded-button border border-border-strong px-5 py-3 font-bold text-white"
                  >
                    Anular
                  </button>
                )}
                {state === "voidable" && confirming === charge.id && (
                  <div className="mt-3 flex flex-col gap-2 rounded-card border border-danger/40 bg-danger/10 p-3">
                    <p className="text-white">
                      Se le devuelven {formatMoney(charge.amount)} a quien lo pagó. El cobro queda
                      en la cuenta, marcado como anulado.
                    </p>
                    <div className="flex gap-2">
                      <button
                        onClick={() => setConfirming(null)}
                        className="flex-1 rounded-button border border-border-strong px-5 py-4 font-bold text-white"
                      >
                        No, volver
                      </button>
                      <button
                        onClick={() => confirm(charge)}
                        disabled={busy}
                        className="flex-1 rounded-button bg-danger px-5 py-4 font-black text-white disabled:opacity-50"
                      >
                        {busy ? "Anulando…" : `Sí, anular ${formatMoney(charge.amount)}`}
                      </button>
                    </div>
                  </div>
                )}
              </li>
            );
          })}
        </ul>
      </div>

      {done && (
        <Banner tone="success" onClose={() => setDone(null)}>
          {done.alreadyVoided
            ? `Ese cobro ya estaba anulado. No se devolvió dos veces.`
            : `Anulado. Se le devolvieron ${formatMoney(done.amount)}.`}
        </Banner>
      )}

      {errorCode && pending && (
        <Banner tone="danger" onClose={() => setErrorCode(null)}>
          <span className="block font-black">{voidErrorMessage(errorCode, pending.amount).title}</span>
          <span className="block">{voidErrorMessage(errorCode, pending.amount).detail}</span>
          {voidErrorMessage(errorCode, pending.amount).action === "retry" && (
            <button
              onClick={() => void run(pending)}
              disabled={busy}
              className="mt-2 rounded-button bg-white/15 px-5 py-3 font-black text-white disabled:opacity-50"
            >
              Reintentar
            </button>
          )}
        </Banner>
      )}
    </div>
  );
}

function Banner({
  tone,
  children,
  onClose,
}: {
  tone: "success" | "danger";
  children: React.ReactNode;
  onClose: () => void;
}) {
  return (
    <div
      className={`border-t p-4 text-lg text-white ${
        tone === "success" ? "border-success/40 bg-success/20" : "border-danger/40 bg-danger/20"
      }`}
    >
      <div className="flex items-start justify-between gap-4">
        <div>{children}</div>
        <button onClick={onClose} className="shrink-0 text-2xl text-white/70">
          ×
        </button>
      </div>
    </div>
  );
}
