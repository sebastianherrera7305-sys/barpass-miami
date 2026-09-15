"use client";

import { useState, type FormEvent } from "react";
import type { HostEventRow, VenueEventRow } from "./types";

/**
 * What is on at this venue, split by WHO is putting it on.
 *
 * · "Your nights" are rows in `public.events` — venue-operator content. The
 *   venue owner creates them here through /api/events, where RLS
 *   ("owners manage own venue events") is what decides they may.
 * · "Hosted at your venue" are `host_events` a promoter anchored to this
 *   venue. The owner cannot edit them — that is someone else's event — but a
 *   bar finding out from BarPass that a promoter is running a night in their
 *   room is the whole point of showing them.
 *
 * host_type comes from a database trigger (supabase/host_event_types.sql), not
 * from anything typed here: claiming to BE the venue requires a venue_owners
 * row, so "Your night" on this list is a fact, not a label someone chose.
 */
export function EventsPanel({
  venueId,
  events,
  hostEvents,
  hostEventsUnavailable,
  onChange,
}: {
  venueId: string;
  events: VenueEventRow[];
  hostEvents: HostEventRow[];
  hostEventsUnavailable: boolean;
  onChange: () => void;
}) {
  const [showForm, setShowForm] = useState(false);
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [startsAt, setStartsAt] = useState("");
  const [endsAt, setEndsAt] = useState("");
  const [coverPrice, setCoverPrice] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  async function handleCreate(e: FormEvent) {
    e.preventDefault();
    setSaving(true);
    setError(null);
    const res = await fetch("/api/events", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        venueId,
        title,
        description: description || undefined,
        startsAt: new Date(startsAt).toISOString(),
        endsAt: endsAt ? new Date(endsAt).toISOString() : undefined,
        coverPrice: coverPrice ? Number(coverPrice) : undefined,
      }),
    });
    setSaving(false);
    if (!res.ok) {
      const json = await res.json().catch(() => ({}));
      setError(json.message ?? json.error ?? "Couldn't post that night.");
      return;
    }
    setTitle("");
    setDescription("");
    setStartsAt("");
    setEndsAt("");
    setCoverPrice("");
    setShowForm(false);
    onChange();
  }

  async function handleDelete(id: string) {
    const res = await fetch(`/api/events/${id}`, { method: "DELETE" });
    if (res.ok) onChange();
    else setError("Couldn't remove that night.");
  }

  return (
    <section className="rounded-xl border border-white/10 bg-white/5 p-4">
      <div className="mb-3 flex items-center justify-between">
        <h2 className="text-sm font-bold text-white/70">Your nights</h2>
        <button onClick={() => setShowForm((s) => !s)} className="text-sm text-amber-400">
          {showForm ? "Cancel" : "+ Post a night"}
        </button>
      </div>

      {showForm && (
        <form onSubmit={handleCreate} className="mb-4 flex flex-col gap-2">
          <Field label="Name" required value={title} onChange={setTitle} placeholder="Ladies Night" />
          <label className="text-xs text-white/40">
            Description (optional)
            <textarea
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              className="mt-1 w-full rounded-lg border border-white/10 bg-black/30 px-3 py-2 text-sm text-white outline-none focus:border-amber-400"
            />
          </label>
          <DateField label="Doors" required value={startsAt} onChange={setStartsAt} />
          <DateField label="Ends (optional)" value={endsAt} onChange={setEndsAt} />
          <Field
            label="Cover in dollars (optional)"
            value={coverPrice}
            onChange={setCoverPrice}
            type="number"
            placeholder="20"
          />
          {error && <p className="text-sm text-red-400">{error}</p>}
          <button
            type="submit"
            disabled={saving}
            className="rounded-lg bg-amber-400 px-4 py-2 text-sm font-bold text-black disabled:opacity-40"
          >
            {saving ? "Posting…" : "Post night"}
          </button>
        </form>
      )}

      <div className="space-y-2">
        {events.length === 0 && (
          <p className="text-sm text-white/40">Nothing posted for tonight or later.</p>
        )}
        {events.map((ev) => (
          <div key={ev.id} className="flex items-start justify-between gap-3 text-sm">
            <div className="min-w-0">
              <p className="truncate text-white">{ev.title}</p>
              <p className="text-white/40">
                {new Date(ev.startsAt).toLocaleString()}
                {ev.coverPrice !== null ? ` · $${ev.coverPrice} cover` : ""}
              </p>
            </div>
            <button onClick={() => handleDelete(ev.id)} className="text-red-400 hover:text-red-300">
              Remove
            </button>
          </div>
        ))}
      </div>

      <div className="mt-5 border-t border-white/10 pt-4">
        <h2 className="mb-2 text-sm font-bold text-white/70">Hosted at your venue</h2>
        {hostEventsUnavailable ? (
          <p className="text-sm text-amber-300/80">
            We couldn&apos;t load promoter events just now — this is not the same as there being
            none. Refresh in a moment.
          </p>
        ) : hostEvents.length === 0 ? (
          <p className="text-sm text-white/40">No promoter is running a published night here.</p>
        ) : (
          <div className="space-y-2">
            {hostEvents.map((ev) => (
              <div key={ev.id} className="flex items-start justify-between gap-3 text-sm">
                <div className="min-w-0">
                  <p className="truncate text-white">{ev.title}</p>
                  <p className="text-white/40">{new Date(ev.startsAt).toLocaleString()}</p>
                </div>
                <span
                  className={
                    ev.hostType === "venue"
                      ? "shrink-0 rounded-full bg-amber-400/20 px-2 py-0.5 text-xs text-amber-300"
                      : "shrink-0 rounded-full bg-white/10 px-2 py-0.5 text-xs text-white/60"
                  }
                >
                  {ev.hostType === "venue" ? "Your night" : ev.hostName ?? "Promoter"}
                </span>
              </div>
            ))}
          </div>
        )}
      </div>
    </section>
  );
}

function Field({
  label,
  value,
  onChange,
  required,
  type = "text",
  placeholder,
}: {
  label: string;
  value: string;
  onChange: (v: string) => void;
  required?: boolean;
  type?: string;
  placeholder?: string;
}) {
  return (
    <label className="text-xs text-white/40">
      {label}
      <input
        required={required}
        type={type}
        min={type === "number" ? 0 : undefined}
        value={value}
        placeholder={placeholder}
        onChange={(e) => onChange(e.target.value)}
        className="mt-1 w-full rounded-lg border border-white/10 bg-black/30 px-3 py-2 text-sm text-white outline-none focus:border-amber-400"
      />
    </label>
  );
}

function DateField(props: { label: string; value: string; onChange: (v: string) => void; required?: boolean }) {
  return <Field {...props} type="datetime-local" />;
}
