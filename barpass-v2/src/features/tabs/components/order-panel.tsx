"use client";

import type { OrderLine } from "@/features/tabs/services/bar-order";
import { formatMoney, linesWithoutPrice } from "@/features/tabs/services/bar-order";

/**
 * El pedido armado y el total, que es lo único que el bartender mira antes de
 * escanear. El total va grande y arriba del botón: se cobra ESE número, y
 * tiene que poder leerse sin acercarse a la tablet.
 */
export function OrderPanel({
  lines,
  onQty,
  total,
  blocker,
  showBlocker,
  freeMode,
  freeAmount,
  onFreeAmount,
  freeDescription,
  onFreeDescription,
  onCharge,
  onClear,
  busy,
}: {
  lines: OrderLine[];
  onQty: (id: string, qty: number) => void;
  total: number;
  blocker: string | null;
  /** El aviso no aparece sobre un pedido vacío: ahí el botón apagado ya lo dice. */
  showBlocker: boolean;
  freeMode: boolean;
  freeAmount: string;
  onFreeAmount: (v: string) => void;
  freeDescription: string;
  onFreeDescription: (v: string) => void;
  onCharge: () => void;
  onClear: () => void;
  busy: boolean;
}) {
  const unpriced = linesWithoutPrice(lines);

  return (
    <aside className="flex w-full flex-col gap-3 rounded-card border border-border-subtle bg-surface p-4 lg:w-[380px]">
      <div className="flex items-center justify-between">
        <h2 className="text-sm font-bold uppercase tracking-[2px] text-text-tertiary">Pedido</h2>
        {lines.length > 0 && (
          <button onClick={onClear} disabled={busy} className="text-sm text-text-secondary underline">
            Vaciar
          </button>
        )}
      </div>

      {freeMode ? (
        <div className="flex flex-col gap-3">
          <p className="text-sm text-text-secondary">
            Sin carta cargada: escribí el monto y qué se llevó.
          </p>
          <input
            inputMode="decimal"
            value={freeAmount}
            onChange={(e) => onFreeAmount(e.target.value)}
            placeholder="0.00"
            className="rounded-field border border-border-subtle bg-white/5 px-4 py-4 text-3xl font-black text-white outline-none focus:border-amber-brand"
          />
          <input
            value={freeDescription}
            onChange={(e) => onFreeDescription(e.target.value)}
            placeholder="Qué consumió (ej: 2 cervezas)"
            maxLength={200}
            className="rounded-field border border-border-subtle bg-white/5 px-4 py-3 text-white outline-none focus:border-amber-brand"
          />
        </div>
      ) : (
        <ul className="flex max-h-[42vh] flex-col gap-2 overflow-y-auto">
          {lines.map((line) => (
            <li
              key={line.id}
              className="flex items-center gap-2 rounded-field border border-border-subtle bg-surface-raised px-3 py-2"
            >
              <div className="min-w-0 flex-1">
                <p className="truncate text-sm font-bold text-white">{line.name}</p>
                <p className="text-xs text-text-secondary">
                  {line.unitPrice === null ? "sin precio" : formatMoney(line.unitPrice)}
                </p>
              </div>
              <button
                onClick={() => onQty(line.id, line.qty - 1)}
                disabled={busy}
                aria-label={`Quitar uno de ${line.name}`}
                className="h-11 w-11 rounded-full bg-white/10 text-xl font-black text-white disabled:opacity-40"
              >
                −
              </button>
              <span className="w-6 text-center text-lg font-black text-white">{line.qty}</span>
              <button
                onClick={() => onQty(line.id, line.qty + 1)}
                disabled={busy}
                aria-label={`Sumar uno de ${line.name}`}
                className="h-11 w-11 rounded-full bg-white/10 text-xl font-black text-white disabled:opacity-40"
              >
                +
              </button>
            </li>
          ))}
          {lines.length === 0 && (
            <li className="py-8 text-center text-text-secondary">Tocá la carta para sumar.</li>
          )}
        </ul>
      )}

      {unpriced.length > 0 && (
        <p className="rounded-field bg-amber-brand/10 px-3 py-2 text-xs text-amber-brand">
          {unpriced.length === 1 ? "Un ítem no tiene" : `${unpriced.length} ítems no tienen`} precio en la carta y suman $0. Cobralo aparte o corregí el pedido.
        </p>
      )}

      <div className="mt-auto flex items-baseline justify-between border-t border-border-subtle pt-4">
        <span className="text-sm font-bold uppercase tracking-[2px] text-text-tertiary">Total</span>
        <span className="text-5xl font-black tabular-nums text-white">{formatMoney(total)}</span>
      </div>

      {blocker && showBlocker && <p className="text-sm text-danger">{blocker}</p>}

      <button
        onClick={onCharge}
        disabled={busy || blocker !== null}
        className="rounded-button bg-amber-brand px-4 py-6 text-2xl font-black text-black disabled:opacity-30"
      >
        Cobrar {formatMoney(total)}
      </button>
    </aside>
  );
}
