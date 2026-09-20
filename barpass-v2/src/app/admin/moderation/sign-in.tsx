"use client";

import { useState, type FormEvent } from "react";
import { createClient } from "@/lib/supabase/client";

/**
 * Same sign-in as the venue dashboard — an ordinary Supabase account. This
 * form proves nothing about authorisation: whether the account may review
 * reports is decided on the server (moderator.ts), which is why signing in
 * successfully can still land you on "this account can't review reports".
 */
export function SignIn({
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
      <h1 className="text-xl font-bold text-white">Moderation</h1>
      <p className="text-sm text-white/40">Sign in with your BarPass staff account.</p>
      <input
        type="email"
        required
        autoComplete="username"
        value={email}
        onChange={(e) => setEmail(e.target.value)}
        placeholder="Email"
        className="rounded-lg border border-white/10 bg-white/5 px-4 py-3 text-white outline-none focus:border-amber-400"
      />
      <input
        type="password"
        required
        autoComplete="current-password"
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
