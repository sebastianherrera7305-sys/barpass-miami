"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { formatMoney, parseScannedToken } from "@/features/tabs/services/bar-order";

/**
 * La cámara, recién al final: el pedido ya está armado y el monto ya está
 * decidido. El cliente abre su código, el bartender escanea, se cobra.
 *
 * `BarcodeDetector` no existe en Safari/iOS ni en Firefox. Ahí no se rompe la
 * noche: se escribe el código a mano, igual que en /validate.
 */

type BarcodeLike = { rawValue: string };
type DetectorLike = { detect: (source: HTMLVideoElement) => Promise<BarcodeLike[]> };

export function ChargeScanner({
  amount,
  onToken,
  onCancel,
}: {
  amount: number;
  onToken: (token: string) => void;
  onCancel: () => void;
}) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const firedRef = useRef(false);
  const [manual, setManual] = useState("");
  const [cameraError, setCameraError] = useState<string | null>(null);

  const stop = useCallback(() => {
    streamRef.current?.getTracks().forEach((t) => t.stop());
    streamRef.current = null;
  }, []);

  const fire = useCallback(
    (raw: string) => {
      const token = parseScannedToken(raw);
      if (!token || firedRef.current) return;
      firedRef.current = true;
      stop();
      onToken(token);
    },
    [onToken, stop],
  );

  useEffect(() => {
    let cancelled = false;

    async function start() {
      if (typeof window === "undefined" || !("BarcodeDetector" in window)) {
        setCameraError("Este navegador no escanea QR. Escribí el código que muestra el cliente.");
        return;
      }
      try {
        const stream = await navigator.mediaDevices.getUserMedia({
          video: { facingMode: "environment" },
        });
        if (cancelled) {
          stream.getTracks().forEach((t) => t.stop());
          return;
        }
        streamRef.current = stream;
        if (videoRef.current) {
          videoRef.current.srcObject = stream;
          await videoRef.current.play();
        }
        const Detector = (window as unknown as { BarcodeDetector: new (o: { formats: string[] }) => DetectorLike })
          .BarcodeDetector;
        const detector = new Detector({ formats: ["qr_code"] });
        const tick = async () => {
          if (cancelled || !videoRef.current || !streamRef.current) return;
          try {
            const codes = await detector.detect(videoRef.current);
            if (codes.length > 0) {
              fire(codes[0].rawValue);
              return;
            }
          } catch {
            // un frame ilegible no es un error: se sigue intentando
          }
          requestAnimationFrame(tick);
        };
        requestAnimationFrame(tick);
      } catch {
        setCameraError("No se pudo abrir la cámara. Escribí el código a mano.");
      }
    }

    void start();
    return () => {
      cancelled = true;
      stop();
    };
  }, [fire, stop]);

  return (
    <div className="fixed inset-0 z-50 flex flex-col items-center justify-center gap-5 bg-black/95 px-6">
      <p className="text-center text-lg text-text-secondary">
        Escaneá el código del cliente para cobrar
      </p>
      <p className="text-6xl font-black tabular-nums text-amber-brand">{formatMoney(amount)}</p>

      {cameraError ? (
        <p className="max-w-sm text-center text-sm text-danger">{cameraError}</p>
      ) : (
        <div className="w-full max-w-md overflow-hidden rounded-card border border-amber-brand/40">
          <video ref={videoRef} className="w-full" muted playsInline />
        </div>
      )}

      <div className="flex w-full max-w-md gap-2">
        <input
          value={manual}
          onChange={(e) => setManual(e.target.value)}
          placeholder="Código manual"
          autoComplete="off"
          className="flex-1 rounded-field border border-border-subtle bg-white/5 px-4 py-4 text-white outline-none focus:border-amber-brand"
        />
        <button
          onClick={() => fire(manual)}
          disabled={!manual.trim()}
          className="rounded-field bg-white/10 px-5 py-4 font-black text-white disabled:opacity-40"
        >
          Cobrar
        </button>
      </div>

      <button onClick={onCancel} className="text-base text-text-secondary underline">
        Cancelar
      </button>
    </div>
  );
}
