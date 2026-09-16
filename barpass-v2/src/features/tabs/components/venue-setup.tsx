"use client";

import { useState } from "react";

/**
 * La configuración de una sola vez. Mismas claves de localStorage que
 * /validate (`bp_venue_id`, `bp_venue_secret`) para que el local que ya
 * configuró la tablet de la puerta no tenga que volver a tipear el secreto.
 *
 * El secreto se escribe y no se vuelve a mostrar nunca: la pantalla de barra
 * queda encendida toda la noche a la vista de cualquiera.
 */
export function VenueSetup({ onSaved }: { onSaved: (venueId: string, secret: string) => void }) {
  const [venueId, setVenueId] = useState("");
  const [secret, setSecret] = useState("");

  return (
    <main className="mx-auto flex min-h-screen max-w-md flex-col justify-center gap-4 px-6">
      <h1 className="text-2xl font-black text-white">Barra BarPass</h1>
      <p className="text-sm text-text-secondary">
        Cargá el ID del local y su código de validación (los provee BarPass). Se guardan en esta
        tablet y no se vuelven a pedir.
      </p>
      <input
        value={venueId}
        onChange={(e) => setVenueId(e.target.value)}
        placeholder="ID del local"
        autoComplete="off"
        className="rounded-field border border-border-subtle bg-white/5 px-4 py-4 text-lg text-white outline-none focus:border-amber-brand"
      />
      <input
        type="password"
        value={secret}
        onChange={(e) => setSecret(e.target.value)}
        placeholder="Código del local"
        autoComplete="off"
        className="rounded-field border border-border-subtle bg-white/5 px-4 py-4 text-lg text-white outline-none focus:border-amber-brand"
      />
      <button
        onClick={() => onSaved(venueId.trim(), secret)}
        disabled={!venueId.trim() || !secret.trim()}
        className="rounded-button bg-amber-brand px-4 py-5 text-lg font-black text-black disabled:opacity-40"
      >
        Empezar a cobrar
      </button>
    </main>
  );
}
