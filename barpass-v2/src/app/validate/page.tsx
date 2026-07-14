"use client";

import { useEffect, useRef, useState } from "react";

/**
 * Door-staff pass validation. Opens on any phone browser — no native app,
 * no App Store listing, no Apple Developer account needed. Staff type the
 * venue's shared secret once (saved locally), then scan or type pass codes.
 */

type Result =
  | { state: "idle" }
  | { state: "checking" }
  | { state: "valid"; venueName: string; kind: string; quantity: number }
  | { state: "already_redeemed"; redeemedAt: string }
  | { state: "expired" }
  | { state: "not_found" }
  | { state: "error"; message: string };

const KIND_LABEL: Record<string, string> = {
  skip_line: "Skip the Line",
  event_ticket: "Entrada al evento",
  table: "Reserva de mesa",
};

export default function ValidatePage() {
  const [secret, setSecret] = useState("");
  const [savedSecret, setSavedSecret] = useState<string | null>(() =>
    typeof window === "undefined" ? null : window.localStorage.getItem("bp_venue_secret"),
  );
  const [code, setCode] = useState("");
  const [result, setResult] = useState<Result>({ state: "idle" });
  const [scanning, setScanning] = useState(false);
  const videoRef = useRef<HTMLVideoElement>(null);
  const streamRef = useRef<MediaStream | null>(null);

  useEffect(() => {
    return () => {
      streamRef.current?.getTracks().forEach((t) => t.stop());
    };
  }, []);

  async function redeem(passCode: string) {
    if (!savedSecret || !passCode.trim()) return;
    setResult({ state: "checking" });
    try {
      const res = await fetch("/api/passes/redeem", {
        method: "POST",
        headers: { "Content-Type": "application/json", "x-venue-secret": savedSecret },
        body: JSON.stringify({ passCode: passCode.trim() }),
      });
      const json = await res.json();
      if (res.ok && json.success) {
        setResult({
          state: "valid",
          venueName: json.pass.venue_name,
          kind: json.pass.kind,
          quantity: json.pass.quantity,
        });
      } else if (json.error === "already_redeemed") {
        setResult({ state: "already_redeemed", redeemedAt: json.redeemedAt });
      } else if (json.error === "expired") {
        setResult({ state: "expired" });
      } else if (json.error === "not_found") {
        setResult({ state: "not_found" });
      } else {
        setResult({ state: "error", message: json.error ?? "unknown_error" });
      }
    } catch {
      setResult({ state: "error", message: "network_error" });
    }
  }

  async function startScan() {
    if (!("BarcodeDetector" in window)) {
      setResult({ state: "error", message: "Este navegador no soporta escaneo de cámara — usa el código manual." });
      return;
    }
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: "environment" } });
      streamRef.current = stream;
      if (videoRef.current) {
        videoRef.current.srcObject = stream;
        await videoRef.current.play();
      }
      setScanning(true);
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const detector = new (window as any).BarcodeDetector({ formats: ["qr_code"] });
      const tick = async () => {
        if (!videoRef.current || !streamRef.current) return;
        try {
          const codes = await detector.detect(videoRef.current);
          if (codes.length > 0) {
            stopScan();
            void redeem(codes[0].rawValue);
            return;
          }
        } catch {
          // keep trying
        }
        if (streamRef.current) requestAnimationFrame(tick);
      };
      requestAnimationFrame(tick);
    } catch {
      setResult({ state: "error", message: "No se pudo acceder a la cámara." });
    }
  }

  function stopScan() {
    streamRef.current?.getTracks().forEach((t) => t.stop());
    streamRef.current = null;
    setScanning(false);
  }

  if (!savedSecret) {
    return (
      <main className="mx-auto flex min-h-screen max-w-sm flex-col justify-center gap-4 px-6">
        <h1 className="text-xl font-bold text-white">Validación BarPass</h1>
        <p className="text-sm text-white/60">
          Ingresá el código de validación del venue (lo provee BarPass).
        </p>
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
    <main className="mx-auto flex min-h-screen max-w-sm flex-col gap-5 px-6 py-10">
      <h1 className="text-xl font-bold text-white">Validar pase</h1>

      {scanning ? (
        <div className="overflow-hidden rounded-xl border border-white/10">
          <video ref={videoRef} className="w-full" muted playsInline />
        </div>
      ) : (
        <button
          onClick={startScan}
          className="rounded-lg border border-amber-400/40 bg-amber-400/10 px-4 py-4 font-bold text-amber-300"
        >
          📷 Escanear QR
        </button>
      )}
      {scanning && (
        <button onClick={stopScan} className="text-sm text-white/50 underline">
          Cancelar escaneo
        </button>
      )}

      <div className="flex gap-2">
        <input
          value={code}
          onChange={(e) => setCode(e.target.value)}
          placeholder="Código manual"
          className="flex-1 rounded-lg border border-white/10 bg-white/5 px-4 py-3 text-white outline-none focus:border-amber-400"
        />
        <button
          onClick={() => redeem(code)}
          disabled={!code.trim()}
          className="rounded-lg bg-white/10 px-4 py-3 font-bold text-white disabled:opacity-40"
        >
          Validar
        </button>
      </div>

      <ResultCard result={result} />

      <button
        onClick={() => {
          window.localStorage.removeItem("bp_venue_secret");
          setSavedSecret(null);
        }}
        className="mt-auto text-xs text-white/30 underline"
      >
        Cambiar código de venue
      </button>
    </main>
  );
}

function ResultCard({ result }: { result: Result }) {
  if (result.state === "idle") return null;
  if (result.state === "checking") {
    return <div className="rounded-xl bg-white/5 px-4 py-6 text-center text-white/60">Verificando…</div>;
  }
  if (result.state === "valid") {
    return (
      <div className="rounded-xl bg-green-500/15 px-4 py-6 text-center">
        <div className="text-4xl">✅</div>
        <div className="mt-2 text-lg font-bold text-green-400">Válido</div>
        <div className="text-sm text-white/70">
          {KIND_LABEL[result.kind] ?? result.kind} · {result.quantity}p · {result.venueName}
        </div>
      </div>
    );
  }
  if (result.state === "already_redeemed") {
    return (
      <div className="rounded-xl bg-red-500/15 px-4 py-6 text-center">
        <div className="text-4xl">⚠️</div>
        <div className="mt-2 text-lg font-bold text-red-400">Ya fue usado</div>
        <div className="text-sm text-white/70">
          Redimido a las {new Date(result.redeemedAt).toLocaleTimeString()}
        </div>
      </div>
    );
  }
  if (result.state === "expired") {
    return (
      <div className="rounded-xl bg-red-500/15 px-4 py-6 text-center">
        <div className="text-4xl">⏰</div>
        <div className="mt-2 text-lg font-bold text-red-400">Expirado</div>
      </div>
    );
  }
  if (result.state === "not_found") {
    return (
      <div className="rounded-xl bg-red-500/15 px-4 py-6 text-center">
        <div className="text-4xl">❌</div>
        <div className="mt-2 text-lg font-bold text-red-400">Código inválido</div>
      </div>
    );
  }
  return (
    <div className="rounded-xl bg-red-500/15 px-4 py-6 text-center">
      <div className="text-4xl">❌</div>
      <div className="mt-2 text-sm text-red-400">{result.message}</div>
    </div>
  );
}
