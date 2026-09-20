"use client";

import { useCallback, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { dismissReports, loadQueue, removeMedia } from "./actions";
import { useBlurPreference } from "./blur-preference";
import { QueueItemCard } from "./queue-item";
import { SignIn } from "./sign-in";
import { ERROR_COPY, type ModerationError, type QueueItem } from "./types";

/**
 * THE REVIEW QUEUE — where a person looks at what was reported and decides.
 *
 * Until this page existed, a photo taken of someone inside a bar at 1am was
 * public, permanent, and had no button anywhere that could take it down.
 * That is an App Store rejection under guideline 1.2, and long before that
 * it is a person with no way out of a photo they never agreed to.
 *
 * Two things this page deliberately never shows:
 *   · WHO REPORTED. Not on screen, not in the payload — the server never
 *     selects the column (actions.ts). Reporting only stays safe while the
 *     reporter is invisible to the moderator.
 *   · WHO POSTED. venue_stories.sql revoked venue_media.user_id from every
 *     client role; a moderation UI is not a reason to hand it back. The
 *     decision here is about the media, and the media is enough to make it.
 *
 * This page holds no key and can read no table. Everything privileged is a
 * Server Action that re-checks the caller on every single call — the client
 * having rendered a queue is never taken as evidence that it was allowed to
 * see one.
 */

export default function ModerationPage() {
  const [supabase] = useState(() => createClient());
  const [checkingSession, setCheckingSession] = useState(true);
  const [token, setToken] = useState<string | null>(null);
  const [email, setEmail] = useState<string | null>(null);

  const [items, setItems] = useState<QueueItem[] | null>(null);
  const [error, setError] = useState<ModerationError | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [loadedAt, setLoadedAt] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [blurred, toggleBlur] = useBlurPreference();

  // A counter, not a refetch function: this project's lint forbids setting
  // state synchronously inside an effect body (react-hooks/
  // set-state-in-effect), so a reload is a dependency change and every
  // state write below happens after an await. Same shape as the venue
  // dashboard.
  const [reloadNonce, setReloadNonce] = useState(0);

  useEffect(() => {
    let active = true;
    supabase.auth.getSession().then(({ data }) => {
      if (!active) return;
      setToken(data.session?.access_token ?? null);
      setEmail(data.session?.user.email ?? null);
      setCheckingSession(false);
    });
    return () => {
      active = false;
    };
  }, [supabase]);

  /**
   * getSession() refreshes an access token that has expired. A moderator
   * leaves this tab open across a whole night; without this, everything
   * would start failing with "not authenticated" an hour in and look like
   * a permissions bug. There is no middleware in this app to do it.
   */
  const currentToken = useCallback(async () => {
    const { data } = await supabase.auth.getSession();
    return data.session?.access_token ?? null;
  }, [supabase]);

  useEffect(() => {
    if (!token) return;
    let active = true;
    (async () => {
      const fresh = await currentToken();
      const result = await loadQueue(fresh);
      if (!active) return;
      setLoading(false);
      if (!result.ok) {
        setError(result.error);
        setItems(null);
        return;
      }
      setError(null);
      setItems(result.items);
      setLoadedAt(result.loadedAt);
    })();
    return () => {
      active = false;
    };
  }, [token, reloadNonce, currentToken]);

  function reload() {
    setLoading(true);
    setNotice(null);
    setReloadNonce((n) => n + 1);
  }

  /** Both decisions end the same way: the item leaves the queue. */
  const settle = useCallback((mediaId: string, warning?: string) => {
    setItems((current) => (current ?? []).filter((i) => i.mediaId !== mediaId));
    setNotice(warning ?? null);
  }, []);

  if (checkingSession) return null;

  if (!token) {
    return (
      <main className="mx-auto flex min-h-screen max-w-sm flex-col justify-center px-6">
        <SignIn
          supabase={supabase}
          onSignedIn={(t, e) => {
            setToken(t);
            setEmail(e);
          }}
        />
      </main>
    );
  }

  return (
    <main className="mx-auto flex min-h-screen max-w-2xl flex-col gap-5 px-6 py-10">
      <header className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-xl font-bold text-white">Reported media</h1>
          <p className="text-xs text-white/40">
            Who reported this isn&apos;t recorded here, for anyone.
          </p>
        </div>
        <button
          onClick={async () => {
            await supabase.auth.signOut();
            setToken(null);
            setItems(null);
          }}
          className="text-sm text-white/40 hover:text-white"
        >
          Sign out {email ? `(${email})` : ""}
        </button>
      </header>

      {error && (
        <p className="rounded-xl border border-red-400/30 bg-red-400/10 p-4 text-sm text-red-200">
          {ERROR_COPY[error]}
        </p>
      )}

      {notice && (
        <p className="rounded-xl border border-amber-400/30 bg-amber-400/10 p-4 text-sm text-amber-200">
          {notice}
        </p>
      )}

      {!error && (
        <div className="flex items-center justify-between text-xs text-white/40">
          <button onClick={toggleBlur} className="hover:text-white">
            {blurred ? "Show previews" : "Blur previews"}
          </button>
          <button onClick={reload} disabled={loading} className="hover:text-white">
            {loading
              ? "Checking…"
              : loadedAt
                ? `Checked ${clockTime(loadedAt)} · Refresh`
                : "Refresh"}
          </button>
        </div>
      )}

      {items && items.length === 0 && !error && <EmptyQueue />}

      {items?.map((item) => (
        <QueueItemCard
          key={item.mediaId}
          item={item}
          blurred={blurred}
          onRemove={async () => {
            const result = await removeMedia(await currentToken(), item.mediaId);
            if (result.ok) settle(item.mediaId, result.warning);
            return result;
          }}
          onDismiss={async () => {
            const result = await dismissReports(await currentToken(), item.mediaId);
            if (result.ok) settle(item.mediaId);
            return result;
          }}
        />
      ))}

      {!items && !error && <p className="text-sm text-white/40">Loading…</p>}
    </main>
  );
}

/**
 * An empty queue is the normal, healthy state — most nights nobody reports
 * anything. It has to read as "all clear" rather than as a screen that
 * failed to load, and it must not invite anyone to go find something to
 * remove.
 */
function EmptyQueue() {
  return (
    <div className="rounded-xl border border-white/10 bg-white/5 p-8 text-center">
      <p className="text-lg font-bold text-white">Nothing to review.</p>
      <p className="mx-auto mt-2 max-w-sm text-sm text-white/50">
        Every report has been dealt with. This is what a normal night looks like — the queue only
        fills when someone taps Report on a photo, and most never do.
      </p>
    </div>
  );
}

function clockTime(iso: string): string {
  const d = new Date(iso);
  return Number.isNaN(d.getTime())
    ? "—"
    : d.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
}
