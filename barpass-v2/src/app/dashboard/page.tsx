"use client";

import { useCallback, useEffect, useState, type FormEvent } from "react";
import { createClient } from "@/lib/supabase/client";
import { ListingPanel } from "./listing-panel";
import { TonightPanel } from "./tonight-panel";
import { EventsPanel } from "./events-panel";
import { PromosPanel } from "./promos-panel";
import { DoorStats } from "./door-stats";
import type { OwnerDashboardData, OwnedVenueSummary } from "./types";

/**
 * The venue's own view of BarPass.
 *
 * Access comes from `venue_owners`, which ops provisions with the service role
 * (supabase/grant_venue_owner.sql). There is no self-serve claim path by
 * design, so "this account isn't linked to a venue" is a normal, expected
 * screen — not an error to hide.
 */
export default function DashboardPage() {
  const [supabase] = useState(() => createClient());
  const [checkingSession, setCheckingSession] = useState(true);
  const [token, setToken] = useState<string | null>(null);
  const [userEmail, setUserEmail] = useState<string | null>(null);

  const [venues, setVenues] = useState<OwnedVenueSummary[] | null>(null);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [data, setData] = useState<OwnerDashboardData | null>(null);
  const [error, setError] = useState<string | null>(null);
  // A counter rather than a refetch function: state must not be set
  // synchronously inside an effect body, so every reload is a dependency
  // change and the fetch's own state writes all happen after an await.
  const [reloadNonce, setReloadNonce] = useState(0);
  const reload = useCallback(() => setReloadNonce((n) => n + 1), []);

  useEffect(() => {
    let active = true;
    supabase.auth.getSession().then(({ data: s }) => {
      if (!active) return;
      setToken(s.session?.access_token ?? null);
      setUserEmail(s.session?.user.email ?? null);
      setCheckingSession(false);
    });
    return () => {
      active = false;
    };
  }, [supabase]);

  // Which venues this account speaks for.
  useEffect(() => {
    let active = true;
    (async () => {
      if (!token) {
        setVenues(null);
        setSelectedId(null);
        setData(null);
        return;
      }
      const res = await fetch("/api/venue-owner/venues", {
        headers: { Authorization: `Bearer ${token}` },
      });
      const json = await res.json().catch(() => ({}));
      if (!active) return;
      if (!res.ok) {
        setError(json.message ?? json.error ?? "Couldn't load your venues.");
        return;
      }
      setVenues(json.venues as OwnedVenueSummary[]);
      setSelectedId((prev) => prev ?? (json.venues[0]?.id ?? null));
    })();
    return () => {
      active = false;
    };
  }, [token]);

  useEffect(() => {
    if (!token || !selectedId) return;
    let active = true;
    (async () => {
      try {
        const res = await fetch(`/api/venue-owner/venues/${selectedId}`, {
          headers: { Authorization: `Bearer ${token}` },
          cache: "no-store",
        });
        const json = await res.json().catch(() => ({}));
        if (!active) return;
        if (!res.ok) {
          setError(json.message ?? json.error ?? "Couldn't load this venue.");
          setData(null);
          return;
        }
        setError(null);
        setData(json as OwnerDashboardData);
      } catch {
        if (active) setError("Network error — check the connection and try again.");
      }
    })();
    return () => {
      active = false;
    };
  }, [token, selectedId, reloadNonce]);

  if (checkingSession) return null;

  if (!token) {
    return (
      <main className="mx-auto flex min-h-screen max-w-sm flex-col justify-center gap-6 px-6">
        <SignIn
          supabase={supabase}
          onSignedIn={(t, email) => {
            setToken(t);
            setUserEmail(email);
          }}
        />
        <DoorStats />
      </main>
    );
  }

  return (
    <main className="mx-auto flex min-h-screen max-w-2xl flex-col gap-5 px-6 py-10">
      <header className="flex items-center justify-between">
        <h1 className="text-xl font-bold text-white">Venue dashboard</h1>
        <button
          onClick={async () => {
            await supabase.auth.signOut();
            setToken(null);
            setUserEmail(null);
          }}
          className="text-sm text-white/40 hover:text-white"
        >
          Sign out {userEmail ? `(${userEmail})` : ""}
        </button>
      </header>

      {venues && venues.length === 0 && (
        <p className="rounded-xl border border-white/10 bg-white/5 p-4 text-sm text-white/60">
          This account isn&apos;t linked to a venue yet. BarPass grants access by hand — send us the
          email you just signed in with and the venue you run, and we&apos;ll switch it on.
        </p>
      )}

      {venues && venues.length > 1 && (
        <select
          value={selectedId ?? ""}
          onChange={(e) => setSelectedId(e.target.value)}
          className="rounded-lg border border-white/10 bg-white/5 px-4 py-3 text-white outline-none focus:border-amber-400"
        >
          {venues.map((v) => (
            <option key={v.id} value={v.id} className="bg-black">
              {v.name}
              {v.listed ? "" : " — hidden"}
            </option>
          ))}
        </select>
      )}

      {error && <p className="text-sm text-red-400">{error}</p>}
      {!data && !error && venues && venues.length > 0 && (
        <p className="text-sm text-white/40">Loading…</p>
      )}

      {/* Guarded on the id so a venue switch never paints the previous
          venue's numbers under the new venue's name. */}
      {data && data.venue.id === selectedId && (
        <>
          <ListingPanel venue={data.venue} />
          <TonightPanel
            tonight={data.tonight}
            recentPasses={data.recentPasses}
            timezone={data.venue.timezone}
          />
          <EventsPanel
            venueId={data.venue.id}
            events={data.events}
            hostEvents={data.hostEvents}
            hostEventsUnavailable={data.hostEventsUnavailable}
            onChange={reload}
          />
          <PromosPanel venueId={data.venue.id} promos={data.promos} onChange={reload} />
        </>
      )}

      <DoorStats />
    </main>
  );
}

function SignIn({
  supabase,
  onSignedIn,
}: {
  supabase: ReturnType<typeof createClient>;
  onSignedIn: (token: string, email: string | null) => void;
}) {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    const { data, error: signInError } = await supabase.auth.signInWithPassword({ email, password });
    setBusy(false);
    if (signInError || !data.session) {
      setError(signInError?.message ?? "Couldn't sign in.");
      return;
    }
    onSignedIn(data.session.access_token, data.session.user.email ?? null);
  }

  return (
    <form onSubmit={handleSubmit} className="flex flex-col gap-3">
      <h1 className="text-xl font-bold text-white">Venue dashboard</h1>
      <p className="text-sm text-white/40">Sign in with the account BarPass linked to your venue.</p>
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
        placeholder="Password"
        className="rounded-lg border border-white/10 bg-white/5 px-4 py-3 text-white outline-none focus:border-amber-400"
      />
      {error && <p className="text-sm text-red-400">{error}</p>}
      <button
        type="submit"
        disabled={busy}
        className="rounded-lg bg-amber-400 px-4 py-3 font-bold text-black disabled:opacity-40"
      >
        {busy ? "Signing in…" : "Sign in"}
      </button>
    </form>
  );
}
