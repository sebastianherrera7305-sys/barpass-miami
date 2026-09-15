"use client";

import { useState, type FormEvent } from "react";
import type { PromoRow } from "./types";

/**
 * Happy hour, 2-for-1, student night — the recurring offers a bar wants in the
 * app between its one-off events. Writes go to /api/promos, where RLS
 * ("owners manage own venue promos") is the check that matters.
 */
export function PromosPanel({
  venueId,
  promos,
  onChange,
}: {
  venueId: string;
  promos: PromoRow[];
  onChange: () => void;
}) {
  const [showForm, setShowForm] = useState(false);
  const [title, setTitle] = useState("");
  const [discountText, setDiscountText] = useState("");
  const [startsAt, setStartsAt] = useState("");
  const [endsAt, setEndsAt] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  async function handleCreate(e: FormEvent) {
    e.preventDefault();
    setSaving(true);
    setError(null);
    const res = await fetch("/api/promos", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        venueId,
        title,
        startsAt: new Date(startsAt).toISOString(),
        endsAt: endsAt ? new Date(endsAt).toISOString() : undefined,
        discountText: discountText || undefined,
      }),
    });
    setSaving(false);
    if (!res.ok) {
      const json = await res.json().catch(() => ({}));
      setError(json.message ?? json.error ?? "Couldn't save that promo.");
      return;
    }
    setTitle("");
    setDiscountText("");
    setStartsAt("");
    setEndsAt("");
    setShowForm(false);
    onChange();
  }

  async function handleDelete(id: string) {
    const res = await fetch(`/api/promos/${id}`, { method: "DELETE" });
    if (res.ok) onChange();
    else setError("Couldn't remove that promo.");
  }

  return (
    <section className="rounded-xl border border-white/10 bg-white/5 p-4">
      <div className="mb-3 flex items-center justify-between">
        <h2 className="text-sm font-bold text-white/70">Promos</h2>
        <button onClick={() => setShowForm((s) => !s)} className="text-sm text-amber-400">
          {showForm ? "Cancel" : "+ New promo"}
        </button>
      </div>

      {showForm && (
        <form onSubmit={handleCreate} className="mb-4 flex flex-col gap-2">
          <label className="text-xs text-white/40">
            Name
            <input
              required
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="Student Thursday"
              className="mt-1 w-full rounded-lg border border-white/10 bg-black/30 px-3 py-2 text-sm text-white outline-none focus:border-amber-400"
            />
          </label>
          <label className="text-xs text-white/40">
            The offer, in your own words
            <input
              value={discountText}
              onChange={(e) => setDiscountText(e.target.value)}
              placeholder="$3 wells until midnight"
              className="mt-1 w-full rounded-lg border border-white/10 bg-black/30 px-3 py-2 text-sm text-white outline-none focus:border-amber-400"
            />
          </label>
          <label className="text-xs text-white/40">
            Starts
            <input
              required
              type="datetime-local"
              value={startsAt}
              onChange={(e) => setStartsAt(e.target.value)}
              className="mt-1 w-full rounded-lg border border-white/10 bg-black/30 px-3 py-2 text-sm text-white outline-none focus:border-amber-400"
            />
          </label>
          <label className="text-xs text-white/40">
            Ends (optional)
            <input
              type="datetime-local"
              value={endsAt}
              onChange={(e) => setEndsAt(e.target.value)}
              className="mt-1 w-full rounded-lg border border-white/10 bg-black/30 px-3 py-2 text-sm text-white outline-none focus:border-amber-400"
            />
          </label>
          {error && <p className="text-sm text-red-400">{error}</p>}
          <button
            type="submit"
            disabled={saving}
            className="rounded-lg bg-amber-400 px-4 py-2 text-sm font-bold text-black disabled:opacity-40"
          >
            {saving ? "Saving…" : "Save promo"}
          </button>
        </form>
      )}

      <div className="space-y-2">
        {promos.length === 0 && <p className="text-sm text-white/40">No promos yet.</p>}
        {promos.map((p) => (
          <div key={p.id} className="flex items-start justify-between gap-3 text-sm">
            <div className="min-w-0">
              <p className="truncate text-white">{p.title}</p>
              <p className="text-white/40">
                {p.discountText ? `${p.discountText} · ` : ""}
                {new Date(p.startsAt).toLocaleString()}
              </p>
            </div>
            <button onClick={() => handleDelete(p.id)} className="text-red-400 hover:text-red-300">
              Remove
            </button>
          </div>
        ))}
      </div>
    </section>
  );
}
