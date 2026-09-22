import { createPrivateKey, createSign } from "node:crypto";
import http2 from "node:http2";
import {
  apnsHeaders,
  isDeadTokenReason,
  MAX_PAYLOAD_BYTES,
  payloadByteLength,
  type ApnsEnvironment,
  type PushKind,
  type PushTarget,
} from "@/lib/safety-push-rules";

/**
 * Minimal APNs HTTP/2 sender — Node built-ins only (`node:http2`,
 * `node:crypto`), no dependency. Token-based auth (.p8), so there is no
 * certificate to renew.
 *
 * Required env (all server-side, never NEXT_PUBLIC_):
 *   APNS_KEY_ID        — the 10-char key id shown next to the .p8 in Apple's portal
 *   APNS_TEAM_ID       — the 10-char Apple Team ID
 *   APNS_PRIVATE_KEY   — the .p8 file contents. Newlines may be written as \n.
 *   APNS_BUNDLE_ID     — optional, defaults to com.sebastian.barpass
 *
 * When any of the first three is missing, `apnsConfig()` returns null and
 * the route answers 503 `push_not_configured`. The hand-raise itself is
 * already saved server-side by then, so a missing key degrades to "people
 * see it when they open the app", not to a lost alert.
 */

export interface ApnsConfig {
  keyId: string;
  teamId: string;
  privateKeyPem: string;
  bundleId: string;
}

export function apnsConfig(env: Record<string, string | undefined> = process.env): ApnsConfig | null {
  const keyId = env.APNS_KEY_ID?.trim();
  const teamId = env.APNS_TEAM_ID?.trim();
  const raw = env.APNS_PRIVATE_KEY?.trim();
  if (!keyId || !teamId || !raw) return null;
  return {
    keyId,
    teamId,
    privateKeyPem: raw.replace(/\\n/g, "\n"),
    bundleId: env.APNS_BUNDLE_ID?.trim() || "com.sebastian.barpass",
  };
}

const base64url = (input: Buffer | string): string =>
  Buffer.from(input).toString("base64").replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");

/** ES256 provider token. Apple accepts one for up to an hour, and throttles
 *  minting a new one more often than every 20 minutes — so it is cached. */
let cachedToken: { value: string; issuedAt: number; keyId: string } | null = null;
const TOKEN_TTL_SECONDS = 50 * 60;

export function providerToken(config: ApnsConfig, nowSeconds = Math.floor(Date.now() / 1000)): string {
  if (
    cachedToken &&
    cachedToken.keyId === config.keyId &&
    nowSeconds - cachedToken.issuedAt < TOKEN_TTL_SECONDS
  ) {
    return cachedToken.value;
  }
  const header = base64url(JSON.stringify({ alg: "ES256", kid: config.keyId }));
  const claims = base64url(JSON.stringify({ iss: config.teamId, iat: nowSeconds }));
  const signingInput = `${header}.${claims}`;
  const signer = createSign("SHA256");
  signer.update(signingInput);
  // JWT wants the raw r||s form, not DER.
  const signature = signer.sign({ key: createPrivateKey(config.privateKeyPem), dsaEncoding: "ieee-p1363" });
  const value = `${signingInput}.${base64url(signature)}`;
  cachedToken = { value, issuedAt: nowSeconds, keyId: config.keyId };
  return value;
}

const HOSTS: Record<ApnsEnvironment, string> = {
  production: "https://api.push.apple.com",
  sandbox: "https://api.sandbox.push.apple.com",
};

export interface SendResult {
  token: string;
  ok: boolean;
  status: number;
  reason?: string;
  /** True when APNs says this token will never work again. */
  dead: boolean;
}

export interface SendOptions {
  kind: PushKind;
  payload: Record<string, unknown>;
  /** Unix seconds after which APNs should stop trying (0 = do not store). */
  expiresAtUnix: number;
  timeoutMs?: number;
}

/**
 * Sends one payload to many tokens, one HTTP/2 connection per environment.
 * Never throws for a per-token failure — those come back as results — so a
 * single dead phone cannot stop the rest of the group from being notified.
 */
export async function sendPush(
  config: ApnsConfig,
  targets: PushTarget[],
  options: SendOptions,
): Promise<SendResult[]> {
  if (payloadByteLength(options.payload) > MAX_PAYLOAD_BYTES) {
    throw new Error("apns_payload_too_large");
  }
  const jwt = providerToken(config);
  const body = JSON.stringify(options.payload);
  const results: SendResult[] = [];

  for (const environment of ["production", "sandbox"] as const) {
    const group = targets.filter((t) => t.environment === environment);
    if (group.length === 0) continue;

    const session = http2.connect(HOSTS[environment]);
    // An unhandled 'error' on the session would crash the route worker.
    let sessionError: string | null = null;
    session.on("error", (err) => {
      sessionError = err.message;
    });

    try {
      const settled = await Promise.all(
        group.map((target) =>
          sendOne(session, jwt, config, target, body, options, () => sessionError),
        ),
      );
      results.push(...settled);
    } finally {
      session.close();
    }
  }
  return results;
}

function sendOne(
  session: http2.ClientHttp2Session,
  jwt: string,
  config: ApnsConfig,
  target: PushTarget,
  body: string,
  options: SendOptions,
  sessionError: () => string | null,
): Promise<SendResult> {
  return new Promise((resolve) => {
    const fail = (status: number, reason: string): void =>
      resolve({ token: target.token, ok: false, status, reason, dead: false });

    if (session.closed || session.destroyed) return fail(0, sessionError() ?? "session_closed");

    let request: http2.ClientHttp2Stream;
    try {
      request = session.request({
        ":method": "POST",
        ":path": `/3/device/${target.token}`,
        authorization: `bearer ${jwt}`,
        "content-type": "application/json",
        ...apnsHeaders(options.kind, config.bundleId, options.expiresAtUnix),
      });
    } catch (error) {
      return fail(0, error instanceof Error ? error.message : "request_failed");
    }

    let status = 0;
    let responseBody = "";
    request.setEncoding("utf8");
    request.setTimeout(options.timeoutMs ?? 8000, () => {
      request.close(http2.constants.NGHTTP2_CANCEL);
      fail(0, "timeout");
    });
    request.on("response", (headers) => {
      status = Number(headers[":status"] ?? 0);
    });
    request.on("data", (chunk: string) => {
      responseBody += chunk;
    });
    request.on("error", (error) => fail(0, error.message));
    request.on("end", () => {
      let reason: string | undefined;
      try {
        reason = responseBody ? (JSON.parse(responseBody) as { reason?: string }).reason : undefined;
      } catch {
        reason = undefined;
      }
      // 200 = APNs ACEPTÓ el aviso para entrega. No dice que llegó ni que
      // alguien lo vio: el teléfono puede estar sin señal. Nada aguas abajo
      // debe presentarlo como "entregado".
      const ok = status === 200;
      resolve({
        token: target.token,
        ok,
        status,
        reason: ok ? undefined : reason,
        dead: !ok && isDeadTokenReason(status, reason),
      });
    });
    request.end(body);
  });
}
