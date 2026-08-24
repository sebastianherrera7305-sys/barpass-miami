"use client";

import { useEffect, useState, type FormEvent } from "react";
import { createClient } from "@/lib/supabase/client";

/**
 * Authenticated venue-owner management section, appended after the
 * existing shared-secret stats view (which stays read-only and untouched).
 * A venue owner signs in with real Supabase Auth, we look up which
 * venue(s) they own via `venue_owners` (RLS-scoped to auth.uid()), and let
 * them create/edit/delete their venue's events and promos. Ownership is
 * enforced by RLS on every write — this UI never trusts itself to decide
 * who owns what.
 */

interface OwnedVenue {
  venueId: string;
  venueName: string;
}

interface EventRow {
  id: string;
  venue_id: string;
  title: string;
  description: string;
  starts_at: string;
  ends_at: string | null;
  cover_price: number | null;
}

interface PromoRow {
  id: string;
  venue_id: string;
  title: string;
  description: string | null;
  starts_at: string;
  ends_at: string | null;
  discount_text: string | null;
}

export function OwnerSection() {
  const supabase = createClient();
  const [checkingSession, setCheckingSession] = useState(true);
  const [userEmail, setUserEmail] = useState<string | null>(null);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [authError, setAuthError] = useState<string | null>(null);
  const [signingIn, setSigningIn] = useState(false);

  const [venues, setVenues] = useState<OwnedVenue[]>([]);
  const [selectedVenueId, setSelectedVenueId] = useState<string | null>(null);
  const [events, setEvents] = useState<EventRow[]>([]);
  const [promos, setPromos] = useState<PromoRow[]>([]);
  const [loadingVenueData, setLoadingVenueData] = useState(false);

  // Restore session on mount.
  useEffect(() => {
    let active = true;
    supabase.auth.getUser().then(({ data }) => {
      if (!active) return;
      setUserEmail(data.user?.email ?? null);
      setCheckingSession(false);
    });
    return () => {
      active = false;
    };
  }, [supabase]);

  // Once signed in, look up owned venues.
  useEffect(() => {
    let active = true;
    (async () => {
      if (!userEmail) {
        if (!active) return;
        setVenues([]);
        setSelectedVenueId(null);
        return;
      }
      const { data, error } = await supabase
        .from("venue_owners")
        .select("venue_id, venues(name)")
        .returns<Array<{ venue_id: string; venues: { name: string } | null }>>();
      if (!active) return;
      if (error) {
        setAuthError(`No pudimos cargar tus venues: ${error.message}`);
        return;
      }
      const owned = (data ?? []).map((row) => ({
        venueId: row.venue_id,
        venueName: row.venues?.name ?? row.venue_id,
      }));
      setVenues(owned);
      setSelectedVenueId((prev) => prev ?? owned[0]?.venueId ?? null);
    })();
    return () => {
      active = false;
    };
  }, [userEmail, supabase]);

  // Load events + promos for the selected venue.
  useEffect(() => {
    let active = true;
    (async () => {
      if (!selectedVenueId) {
        if (!active) return;
        setEvents([]);
        setPromos([]);
        return;
      }
      setLoadingVenueData(true);
      const [eventsRes, promosRes] = await Promise.all([
        supabase
          .from("events")
          .select("*")
          .eq("venue_id", selectedVenueId)
          .order("starts_at", { ascending: false }),
        supabase
          .from("promos")
          .select("*")
          .eq("venue_id", selectedVenueId)
          .order("starts_at", { ascending: false }),
      ]);
      if (!active) return;
      setEvents((eventsRes.data as EventRow[]) ?? []);
      setPromos((promosRes.data as PromoRow[]) ?? []);
      setLoadingVenueData(false);
    })();
    return () => {
      active = false;
    };
  }, [selectedVenueId, supabase]);

  async function handleSignIn(e: FormEvent) {
    e.preventDefault();
    setSigningIn(true);
    setAuthError(null);
    const { data, error } = await supabase.auth.signInWithPassword({ email, password });
    setSigningIn(false);
    if (error) {
      setAuthError(error.message);
      return;
    }
    setUserEmail(data.user?.email ?? email);
  }

  async function handleSignOut() {
    await supabase.auth.signOut();
    setUserEmail(null);
    setEmail("");
    setPassword("");
  }

  async function refreshVenueData() {
    if (!selectedVenueId) return;
    const [eventsRes, promosRes] = await Promise.all([
      supabase.from("events").select("*").eq("venue_id", selectedVenueId).order("starts_at", { ascending: false }),
      supabase.from("promos").select("*").eq("venue_id", selectedVenueId).order("starts_at", { ascending: false }),
    ]);
    setEvents((eventsRes.data as EventRow[]) ?? []);
    setPromos((promosRes.data as PromoRow[]) ?? []);
  }

  if (checkingSession) return null;

  return (
    <section className="mt-10 border-t border-white/10 pt-8">
      <h2 className="mb-1 text-lg font-bold text-white">Panel del venue</h2>
      <p className="mb-4 text-sm text-white/40">
        Inicia sesión con tu cuenta de venue para administrar eventos y promos.
      </p>

      {!userEmail ? (
        <form onSubmit={handleSignIn} className="flex max-w-sm flex-col gap-3">
          <input
            type="email"
            required
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="Email"
            className="rounded-lg border border-white/10 bg-white/5 px-4 py-3 text-white outline-none focus:border-amber-400"
          />
          <input
            type="password"
            required
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            placeholder="Contraseña"
            className="rounded-lg border border-white/10 bg-white/5 px-4 py-3 text-white outline-none focus:border-amber-400"
          />
          {authError && <p className="text-sm text-red-400">{authError}</p>}
          <button
            type="submit"
            disabled={signingIn}
            className="rounded-lg bg-amber-400 px-4 py-3 font-bold text-black disabled:opacity-40"
          >
            {signingIn ? "Ingresando…" : "Iniciar sesión"}
          </button>
        </form>
      ) : (
        <div className="flex flex-col gap-6">
          <div className="flex items-center justify-between">
            <p className="text-sm text-white/60">
              Sesión: <span className="text-white">{userEmail}</span>
            </p>
            <button onClick={handleSignOut} className="text-sm text-white/40 hover:text-white">
              Cerrar sesión
            </button>
          </div>

          {authError && <p className="text-sm text-red-400">{authError}</p>}

          {venues.length === 0 ? (
            <p className="text-sm text-white/40">
              Esta cuenta no tiene ningún venue asignado. Contacta a BarPass ops.
            </p>
          ) : (
            <>
              {venues.length > 1 && (
                <select
                  value={selectedVenueId ?? ""}
                  onChange={(e) => setSelectedVenueId(e.target.value)}
                  className="rounded-lg border border-white/10 bg-white/5 px-4 py-3 text-white outline-none focus:border-amber-400"
                >
                  {venues.map((v) => (
                    <option key={v.venueId} value={v.venueId} className="bg-black">
                      {v.venueName}
                    </option>
                  ))}
                </select>
              )}

              {selectedVenueId && (
                <>
                  {loadingVenueData && <p className="text-sm text-white/40">Cargando…</p>}
                  <EventsManager venueId={selectedVenueId} events={events} onChange={refreshVenueData} />
                  <PromosManager venueId={selectedVenueId} promos={promos} onChange={refreshVenueData} />
                </>
              )}
            </>
          )}
        </div>
      )}
    </section>
  );
}

// ── Events ────────────────────────────────────────────────────

function EventsManager({
  venueId,
  events,
  onChange,
}: {
  venueId: string;
  events: EventRow[];
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
      setError(json.error ?? "No se pudo crear el evento");
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
  }

  return (
    <div className="rounded-xl border border-white/10 bg-white/5 p-4">
      <div className="mb-3 flex items-center justify-between">
        <h3 className="text-sm font-bold text-white/70">Eventos</h3>
        <button onClick={() => setShowForm((s) => !s)} className="text-sm text-amber-400">
          {showForm ? "Cancelar" : "+ Nuevo evento"}
        </button>
      </div>

      {showForm && (
        <form onSubmit={handleCreate} className="mb-4 flex flex-col gap-2">
          <input
            required
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder="Título"
            className="rounded-lg border border-white/10 bg-black/30 px-3 py-2 text-sm text-white outline-none focus:border-amber-400"
          />
          <textarea
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            placeholder="Descripción (opcional)"
            className="rounded-lg border border-white/10 bg-black/30 px-3 py-2 text-sm text-white outline-none focus:border-amber-400"
          />
          <label className="text-xs text-white/40">
            Empieza
            <input
              required
              type="datetime-local"
              value={startsAt}
              onChange={(e) => setStartsAt(e.target.value)}
              className="mt-1 w-full rounded-lg border border-white/10 bg-black/30 px-3 py-2 text-sm text-white outline-none focus:border-amber-400"
            />
          </label>
          <label className="text-xs text-white/40">
            Termina (opcional)
            <input
              type="datetime-local"
              value={endsAt}
              onChange={(e) => setEndsAt(e.target.value)}
              className="mt-1 w-full rounded-lg border border-white/10 bg-black/30 px-3 py-2 text-sm text-white outline-none focus:border-amber-400"
            />
          </label>
          <input
            type="number"
            min={0}
            value={coverPrice}
            onChange={(e) => setCoverPrice(e.target.value)}
            placeholder="Cover ($, opcional)"
            className="rounded-lg border border-white/10 bg-black/30 px-3 py-2 text-sm text-white outline-none focus:border-amber-400"
          />
          {error && <p className="text-sm text-red-400">{error}</p>}
          <button
            type="submit"
            disabled={saving}
            className="rounded-lg bg-amber-400 px-4 py-2 text-sm font-bold text-black disabled:opacity-40"
          >
            {saving ? "Guardando…" : "Guardar evento"}
          </button>
        </form>
      )}

      <div className="space-y-2">
        {events.length === 0 && <p className="text-sm text-white/40">Sin eventos todavía.</p>}
        {events.map((ev) => (
          <div key={ev.id} className="flex items-center justify-between text-sm">
            <div>
              <p className="text-white">{ev.title}</p>
              <p className="text-white/40">{new Date(ev.starts_at).toLocaleString()}</p>
            </div>
            <button onClick={() => handleDelete(ev.id)} className="text-red-400 hover:text-red-300">
              Eliminar
            </button>
          </div>
        ))}
      </div>
    </div>
  );
}

// ── Promos ────────────────────────────────────────────────────

function PromosManager({
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
  const [description, setDescription] = useState("");
  const [startsAt, setStartsAt] = useState("");
  const [endsAt, setEndsAt] = useState("");
  const [discountText, setDiscountText] = useState("");
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
        description: description || undefined,
        startsAt: new Date(startsAt).toISOString(),
        endsAt: endsAt ? new Date(endsAt).toISOString() : undefined,
        discountText: discountText || undefined,
      }),
    });
    setSaving(false);
    if (!res.ok) {
      const json = await res.json().catch(() => ({}));
      setError(json.error ?? "No se pudo crear la promo");
      return;
    }
    setTitle("");
    setDescription("");
    setStartsAt("");
    setEndsAt("");
    setDiscountText("");
    setShowForm(false);
    onChange();
  }

  async function handleDelete(id: string) {
    const res = await fetch(`/api/promos/${id}`, { method: "DELETE" });
    if (res.ok) onChange();
  }

  return (
    <div className="rounded-xl border border-white/10 bg-white/5 p-4">
      <div className="mb-3 flex items-center justify-between">
        <h3 className="text-sm font-bold text-white/70">Promos</h3>
        <button onClick={() => setShowForm((s) => !s)} className="text-sm text-amber-400">
          {showForm ? "Cancelar" : "+ Nueva promo"}
        </button>
      </div>

      {showForm && (
        <form onSubmit={handleCreate} className="mb-4 flex flex-col gap-2">
          <input
            required
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder="Título"
            className="rounded-lg border border-white/10 bg-black/30 px-3 py-2 text-sm text-white outline-none focus:border-amber-400"
          />
          <textarea
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            placeholder="Descripción (opcional)"
            className="rounded-lg border border-white/10 bg-black/30 px-3 py-2 text-sm text-white outline-none focus:border-amber-400"
          />
          <input
            value={discountText}
            onChange={(e) => setDiscountText(e.target.value)}
            placeholder='Descuento (ej: "2x1 en tragos")'
            className="rounded-lg border border-white/10 bg-black/30 px-3 py-2 text-sm text-white outline-none focus:border-amber-400"
          />
          <label className="text-xs text-white/40">
            Empieza
            <input
              required
              type="datetime-local"
              value={startsAt}
              onChange={(e) => setStartsAt(e.target.value)}
              className="mt-1 w-full rounded-lg border border-white/10 bg-black/30 px-3 py-2 text-sm text-white outline-none focus:border-amber-400"
            />
          </label>
          <label className="text-xs text-white/40">
            Termina (opcional)
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
            {saving ? "Guardando…" : "Guardar promo"}
          </button>
        </form>
      )}

      <div className="space-y-2">
        {promos.length === 0 && <p className="text-sm text-white/40">Sin promos todavía.</p>}
        {promos.map((p) => (
          <div key={p.id} className="flex items-center justify-between text-sm">
            <div>
              <p className="text-white">{p.title}</p>
              <p className="text-white/40">
                {p.discount_text ?? ""} · {new Date(p.starts_at).toLocaleString()}
              </p>
            </div>
            <button onClick={() => handleDelete(p.id)} className="text-red-400 hover:text-red-300">
              Eliminar
            </button>
          </div>
        ))}
      </div>
    </div>
  );
}
