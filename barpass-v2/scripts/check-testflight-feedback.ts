/**
 * Revisa feedback nuevo de TestFlight (screenshots + crashes) vía la App
 * Store Connect API, y guarda lo que no vimos todavía en Supabase
 * (tabla `testflight_feedback`, ver supabase/testflight_feedback.sql).
 *
 * Auth: JWT firmado ES256 con la private key de la API key de App Store
 * Connect — sin dependencias nuevas, usa el módulo `crypto` nativo de Node.
 *
 * Uso: npm run check:feedback
 * Imprime "NUEVO: N items" seguido del detalle si hay algo nuevo, o
 * "sin novedades" si no hay nada — la tarea programada de Claude Code lee
 * esta salida para decidir si avisa al usuario.
 *
 * Requiere en .env.local:
 *   ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY_PATH,
 *   NEXT_PUBLIC_SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
 */
import { createClient } from "@supabase/supabase-js";
import { createSign, createPrivateKey } from "node:crypto";
import { readFileSync } from "node:fs";
// @ts-expect-error — mismo fallback de transporte que los otros scripts
import ws from "ws";

const KEY_ID = process.env.ASC_KEY_ID;
const ISSUER_ID = process.env.ASC_ISSUER_ID;
const KEY_PATH = process.env.ASC_PRIVATE_KEY_PATH;
const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const APP_ID = "6791393970"; // BarPass en App Store Connect

if (!KEY_ID || !ISSUER_ID || !KEY_PATH || !SUPABASE_URL || !SERVICE_ROLE_KEY) {
  console.error("Faltan env vars: ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY_PATH, NEXT_PUBLIC_SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY");
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  realtime: { transport: ws as unknown as typeof WebSocket },
});

function base64url(input: Buffer | string): string {
  return Buffer.from(input as never)
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

/** JWT firmado ES256, válido 19 minutos (el máximo de Apple es 20). */
function makeToken(): string {
  const header = { alg: "ES256", kid: KEY_ID, typ: "JWT" };
  const now = Math.floor(Date.now() / 1000);
  const payload = { iss: ISSUER_ID, iat: now, exp: now + 19 * 60, aud: "appstoreconnect-v1" };
  const signingInput = `${base64url(JSON.stringify(header))}.${base64url(JSON.stringify(payload))}`;

  const pem = readFileSync(KEY_PATH!, "utf8");
  const key = createPrivateKey(pem);
  const signer = createSign("SHA256");
  signer.update(signingInput);
  // ES256 en JWT usa el formato IEEE P1363 (r||s), no el DER que Node firma
  // por default — dsaEncoding lo pide directo en el formato correcto.
  const signature = signer.sign({ key, dsaEncoding: "ieee-p1363" });

  return `${signingInput}.${base64url(signature)}`;
}

async function apiGet(path: string): Promise<any> {
  const token = makeToken();
  const res = await fetch(`https://api.appstoreconnect.apple.com/v1${path}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!res.ok) throw new Error(`${path} -> ${res.status}: ${await res.text()}`);
  return res.json();
}

interface FeedbackRow {
  external_id: string;
  kind: "screenshot" | "crash";
  comment: string | null;
  tester_email: string | null;
  device_model: string | null;
  os_version: string | null;
  app_version: string | null;
  submitted_at: string;
}

async function fetchScreenshots(): Promise<FeedbackRow[]> {
  const data = await apiGet(
    `/apps/${APP_ID}/betaFeedbackScreenshotSubmissions?limit=50` +
      `&fields[betaFeedbackScreenshotSubmissions]=comment,deviceModel,osVersion,appPlatform,createdDate,email`
  );
  return (data.data ?? []).map((d: any) => ({
    external_id: d.id,
    kind: "screenshot" as const,
    comment: d.attributes?.comment ?? null,
    tester_email: d.attributes?.email ?? null,
    device_model: d.attributes?.deviceModel ?? null,
    os_version: d.attributes?.osVersion ?? null,
    app_version: d.attributes?.appVersion ?? null,
    submitted_at: d.attributes?.createdDate,
  }));
}

async function fetchCrashes(): Promise<FeedbackRow[]> {
  const data = await apiGet(
    `/apps/${APP_ID}/betaFeedbackCrashSubmissions?limit=50` +
      `&fields[betaFeedbackCrashSubmissions]=comment,deviceModel,osVersion,appPlatform,createdDate,email`
  );
  return (data.data ?? []).map((d: any) => ({
    external_id: d.id,
    kind: "crash" as const,
    comment: d.attributes?.comment ?? null,
    tester_email: d.attributes?.email ?? null,
    device_model: d.attributes?.deviceModel ?? null,
    os_version: d.attributes?.osVersion ?? null,
    app_version: d.attributes?.appVersion ?? null,
    submitted_at: d.attributes?.createdDate,
  }));
}

async function main() {
  const [screenshots, crashes] = await Promise.all([fetchScreenshots(), fetchCrashes()]);
  const all: FeedbackRow[] = [...screenshots, ...crashes];

  const { data: existing } = await supabase.from("testflight_feedback").select("external_id");
  const seen = new Set((existing ?? []).map((r) => r.external_id));
  const fresh = all.filter((r) => !seen.has(r.external_id));

  if (fresh.length === 0) {
    console.log("sin novedades");
    return;
  }

  const { error } = await supabase.from("testflight_feedback").insert(fresh);
  if (error) {
    console.error("ERROR guardando en Supabase:", error.message);
    process.exit(1);
  }

  console.log(`NUEVO: ${fresh.length} items`);
  for (const item of fresh) {
    console.log(`- [${item.kind}] ${item.tester_email ?? "?"} (${item.device_model ?? "?"}, iOS ${item.os_version ?? "?"}): ${item.comment ?? "(sin comentario)"}`);
  }
}

main();
