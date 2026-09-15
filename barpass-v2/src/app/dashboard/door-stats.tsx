"use client";

import { useState } from "react";

/**
 * The original shared-secret view, kept for door staff who have no BarPass
 * account — same audience as /validate, which uses the same secret.
 *
 * Two things were broken here and are fixed: it asked for the venue id with
 * the example "liv-miami", but `venue_secrets.venue_id` is a uuid FK and
 * `orders.vendor_id` / `passes.venue_id` hold that uuid as text — a slug
 * matched nothing, so this screen could only ever answer "venue_not_found".
 * And its revenue line double-counted card-paid passes; that sum now comes
 * from the shared summariser.
 */
interface Stats {
  revenueToday: number;
  ordersToday: number;
  passesIssuedToday: number;
  passesRedeemedToday: number;
}

export function DoorStats() {
  const [venueId, setVenueId] = useState("");
  const [secret, setSecret] = useState("");
  const [stats, setStats] = useState<Stats | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function load() {
    setLoading(true);
    setError(null);
    setStats(null);
    try {
      const res = await fetch(`/api/venue/stats?venueId=${encodeURIComponent(venueId.trim())}`, {
        headers: { "x-venue-secret": secret },
      });
      const json = await res.json();
      if (!res.ok || json.error) setError(json.message ?? json.error ?? "request_failed");
      else setStats(json as Stats);
    } catch {
      setError("network_error");
    } finally {
      setLoading(false);
    }
  }

  return (
    <details className="rounded-xl border border-white/10 bg-white/5 p-4">
      <summary className="cursor-pointer text-sm font-bold text-white/70">
        Door staff without a BarPass account
      </summary>
      <p className="mt-2 text-xs text-white/40">
        Uses the venue code BarPass gave you, plus the venue&apos;s id (the long
        0000-0000 style id, not the web address).
      </p>
      <div className="mt-3 flex flex-col gap-2">
        <input
          value={venueId}
          onChange={(e) => setVenueId(e.target.value)}
          placeholder="Venue id (uuid)"
          className="rounded-lg border border-white/10 bg-black/30 px-3 py-2 text-sm text-white outline-none focus:border-amber-400"
        />
        <input
          type="password"
          value={secret}
          onChange={(e) => setSecret(e.target.value)}
          placeholder="Venue code"
          className="rounded-lg border border-white/10 bg-black/30 px-3 py-2 text-sm text-white outline-none focus:border-amber-400"
        />
        <button
          onClick={load}
          disabled={!venueId.trim() || !secret.trim() || loading}
          className="rounded-lg bg-white/10 px-4 py-2 text-sm font-bold text-white disabled:opacity-40"
        >
          {loading ? "Loading…" : "Show today"}
        </button>
        {error && <p className="text-sm text-red-400">{error}</p>}
        {stats && (
          <p className="text-sm text-white/70">
            ${stats.revenueToday.toFixed(2)} · {stats.ordersToday} orders ·{" "}
            {stats.passesRedeemedToday}/{stats.passesIssuedToday} passes used
          </p>
        )}
      </div>
    </details>
  );
}
