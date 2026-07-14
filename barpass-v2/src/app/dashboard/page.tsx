"use client";

import { useEffect, useState } from "react";

/**
 * Basic venue dashboard — today's revenue, orders, and pass redemption
 * numbers. Reuses the same shared venue secret as /validate (same
 * audience: venue staff, not customers).
 */

interface Stats {
  venueId: string;
  revenueToday: number;
  ordersToday: number;
  passesIssuedToday: number;
  passesRedeemedToday: number;
  recentPasses: Array<{ id: string; kind: string; quantity: number; amount: number; redeemed_at: string | null; created_at: string }>;
}

export default function DashboardPage() {
  const [secret, setSecret] = useState("");
  const [savedSecret, setSavedSecret] = useState<string | null>(() =>
    typeof window === "undefined" ? null : window.localStorage.getItem("bp_venue_secret"),
  );
  const [venueId, setVenueId] = useState("");
  const [stats, setStats] = useState<Stats | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!savedSecret || !venueId) return;
    const controller = new AbortController();

    async function run() {
      setLoading(true);
      setError(null);
      try {
        const res = await fetch(`/api/venue/stats?venueId=${encodeURIComponent(venueId)}`, {
          headers: { "x-venue-secret": savedSecret! },
          signal: controller.signal,
        });
        const json = await res.json();
        if (json.error) setError(json.error);
        else setStats(json);
      } catch {
        setError("network_error");
      } finally {
        setLoading(false);
      }
    }
    void run();

    return () => controller.abort();
  }, [savedSecret, venueId]);

  if (!savedSecret) {
    return (
      <main className="mx-auto flex min-h-screen max-w-sm flex-col justify-center gap-4 px-6">
        <h1 className="text-xl font-bold text-white">Dashboard BarPass</h1>
        <input
          type="password"
          value={secret}
          onChange={(e) => setSecret(e.target.value)}
          placeholder="Código del venue"
          className="rounded-lg border border-white/10 bg-white/5 px-4 py-3 text-white outline-none focus:border-amber-400"
        />
        <button
          onClick={() => {
            window.localStorage.setItem("bp_venue_secret", secret);
            setSavedSecret(secret);
          }}
          disabled={!secret.trim()}
          className="rounded-lg bg-amber-400 px-4 py-3 font-bold text-black disabled:opacity-40"
        >
          Continuar
        </button>
      </main>
    );
  }

  return (
    <main className="mx-auto flex min-h-screen max-w-lg flex-col gap-5 px-6 py-10">
      <h1 className="text-xl font-bold text-white">Dashboard de hoy</h1>
      <input
        value={venueId}
        onChange={(e) => setVenueId(e.target.value)}
        placeholder="ID del venue (ej: liv-miami)"
        className="rounded-lg border border-white/10 bg-white/5 px-4 py-3 text-white outline-none focus:border-amber-400"
      />

      {loading && <p className="text-sm text-white/50">Cargando…</p>}
      {error && <p className="text-sm text-red-400">Error: {error}</p>}

      {stats && (
        <>
          <div className="grid grid-cols-2 gap-3">
            <StatCard label="Revenue hoy" value={`$${stats.revenueToday.toFixed(2)}`} />
            <StatCard label="Órdenes" value={String(stats.ordersToday)} />
            <StatCard label="Pases emitidos" value={String(stats.passesIssuedToday)} />
            <StatCard label="Pases usados" value={String(stats.passesRedeemedToday)} />
          </div>

          <div className="rounded-xl border border-white/10 bg-white/5 p-4">
            <h2 className="mb-3 text-sm font-bold text-white/70">Pases recientes</h2>
            <div className="space-y-2">
              {stats.recentPasses.length === 0 && (
                <p className="text-sm text-white/40">Nada todavía hoy.</p>
              )}
              {stats.recentPasses.map((p) => (
                <div key={p.id} className="flex justify-between text-sm">
                  <span className="text-white/70">{p.kind} · {p.quantity}p</span>
                  <span className={p.redeemed_at ? "text-green-400" : "text-amber-400"}>
                    {p.redeemed_at ? "Usado" : "Activo"} · ${Number(p.amount).toFixed(2)}
                  </span>
                </div>
              ))}
            </div>
          </div>
        </>
      )}
    </main>
  );
}

function StatCard({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-xl border border-white/10 bg-white/5 p-4">
      <p className="text-xs text-white/40">{label}</p>
      <p className="mt-1 text-2xl font-bold text-white">{value}</p>
    </div>
  );
}
