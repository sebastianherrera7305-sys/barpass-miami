"use client";

import { useMemo, useState } from "react";
import type { MenuItem } from "@/features/tabs/services/menu-client";
import { formatMoney } from "@/features/tabs/services/bar-order";

/**
 * La carta del local, para armar el pedido con el pulgar. Un tap = una unidad;
 * el buscador filtra por nombre y categoría porque una carta de 45 ítems no
 * entra en una pantalla y scrollear con una mano ocupada no es una opción.
 */
export function MenuPicker({
  items,
  loading,
  onAdd,
  disabled,
}: {
  items: MenuItem[];
  loading: boolean;
  onAdd: (item: MenuItem) => void;
  disabled?: boolean;
}) {
  const [query, setQuery] = useState("");

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return items;
    return items.filter(
      (i) => i.name.toLowerCase().includes(q) || i.category.toLowerCase().includes(q),
    );
  }, [items, query]);

  return (
    <div className="flex min-h-0 flex-1 flex-col gap-3">
      <input
        value={query}
        onChange={(e) => setQuery(e.target.value)}
        placeholder="Buscar en la carta…"
        className="w-full rounded-field border border-border-subtle bg-white/5 px-4 py-4 text-lg text-white outline-none focus:border-amber-brand"
      />

      {loading ? (
        <p className="py-10 text-center text-text-secondary">Cargando la carta…</p>
      ) : filtered.length === 0 ? (
        <p className="py-10 text-center text-text-secondary">
          {items.length === 0 ? "Este local no tiene carta cargada." : "Nada con ese nombre."}
        </p>
      ) : (
        <div className="grid min-h-0 flex-1 auto-rows-min grid-cols-2 gap-3 overflow-y-auto pb-4 sm:grid-cols-3">
          {filtered.map((item) => (
            <button
              key={item.id}
              onClick={() => onAdd(item)}
              disabled={disabled}
              className="flex h-24 flex-col justify-between rounded-card border border-border-subtle bg-surface-raised p-3 text-left active:border-amber-brand active:bg-amber-brand/10 disabled:opacity-40"
            >
              <span className="line-clamp-2 text-sm font-bold leading-tight text-white">
                {item.name}
              </span>
              <span
                className={
                  item.price === null
                    ? "text-sm font-bold text-text-tertiary"
                    : "text-lg font-black text-amber-brand"
                }
              >
                {item.price === null ? "sin precio" : formatMoney(item.price)}
              </span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
