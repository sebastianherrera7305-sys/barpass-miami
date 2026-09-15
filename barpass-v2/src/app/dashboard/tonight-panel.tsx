"use client";

import type { OwnerDashboardData } from "./types";

/**
 * Tonight's money and door count, for the venue's own calendar day (computed
 * in the venue's timezone server-side, not the server's).
 *
 * Revenue counts each sale once: a card-paid pass writes both an `orders` row
 * and a `passes` row, and the old dashboard added both together.
 */
export function TonightPanel({
  tonight,
  recentPasses,
  timezone,
}: {
  tonight: OwnerDashboardData["tonight"];
  recentPasses: OwnerDashboardData["recentPasses"];
  timezone: string | null;
}) {
  return (
    <section className="flex flex-col gap-3">
      <div className="flex items-baseline justify-between">
        <h2 className="text-sm font-bold text-white/70">Today</h2>
        {timezone && <span className="text-xs text-white/30">{timezone}</span>}
      </div>

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <Stat label="Revenue" value={`$${tonight.revenue.toFixed(2)}`} />
        <Stat label="Orders" value={String(tonight.orders)} />
        <Stat label="Passes sold" value={String(tonight.passesIssued)} />
        <Stat
          label="Checked in"
          value={`${tonight.passesRedeemed}/${tonight.passesIssued}`}
          hint={`${tonight.guestsOnPasses} guests covered`}
        />
      </div>

      <div className="rounded-xl border border-white/10 bg-white/5 p-4">
        <h3 className="mb-3 text-sm font-bold text-white/70">Passes today</h3>
        {recentPasses.length === 0 ? (
          <p className="text-sm text-white/40">Nothing yet today.</p>
        ) : (
          <div className="space-y-2">
            {recentPasses.map((p) => (
              <div key={p.id} className="flex justify-between text-sm">
                <span className="text-white/70">
                  {p.kind.replace(/_/g, " ")} · {p.quantity}p
                </span>
                <span className={p.redeemedAt ? "text-green-400" : "text-amber-400"}>
                  {p.redeemedAt ? "Used" : "Active"} · ${p.amount.toFixed(2)}
                </span>
              </div>
            ))}
          </div>
        )}
      </div>
    </section>
  );
}

function Stat({ label, value, hint }: { label: string; value: string; hint?: string }) {
  return (
    <div className="rounded-xl border border-white/10 bg-white/5 p-4">
      <p className="text-xs text-white/40">{label}</p>
      <p className="mt-1 text-2xl font-bold text-white">{value}</p>
      {hint && <p className="mt-1 text-xs text-white/30">{hint}</p>}
    </div>
  );
}
