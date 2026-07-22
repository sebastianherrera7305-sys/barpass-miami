import { createClient as createServiceClient } from "@supabase/supabase-js";

/**
 * Rate limiting sin dependencia externa — usa la función RPC
 * check_rate_limit (supabase/rate_limits_schema.sql), que hace un upsert
 * atómico por ventana de tiempo, mismo patrón que adjust_wallet_balance.
 *
 * Fail-open a propósito: si Supabase no está configurado o el RPC falla,
 * NO bloqueamos la request. Un rate limiter roto no debe tumbar pagos
 * reales — es una red de seguridad, no el camino crítico.
 *
 * OBSERVABILITY (Phase 0 hardening): fail-open used to be silent — a
 * misconfigured env var or a revoked RPC grant would quietly disable
 * every rate limit in production with zero signal anywhere. This is
 * exactly what happened after the Phase 1 RPC lockdown migration: nothing
 * ever showed up as broken except "rate_limits never gets any rows,"
 * which is invisible unless someone thinks to check that table. Every
 * fail-open path below now logs the RPC name, Supabase error code/message,
 * and a request id to correlate against Vercel's logs — but the id and
 * error detail never reach the client, which always gets a generic
 * boolean back.
 */
export async function checkRateLimit(
  key: string,
  { maxRequests, windowSeconds }: { maxRequests: number; windowSeconds: number },
): Promise<boolean> {
  const requestId = crypto.randomUUID();
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!supabaseUrl || !serviceRoleKey) {
    console.error("[rate-limit] fail-open: missing Supabase env vars", {
      requestId,
      rpc: "check_rate_limit",
      key,
      hasUrl: Boolean(supabaseUrl),
      hasServiceRoleKey: Boolean(serviceRoleKey),
    });
    return true;
  }

  const supabase = createServiceClient(supabaseUrl, serviceRoleKey);
  const { data, error } = await supabase.rpc("check_rate_limit", {
    p_key: key,
    p_max_requests: maxRequests,
    p_window_seconds: windowSeconds,
  });
  if (error) {
    console.error("[rate-limit] fail-open: check_rate_limit RPC failed", {
      requestId,
      rpc: "check_rate_limit",
      key,
      code: error.code,
      message: error.message,
      hint: error.hint,
    });
    return true;
  }
  return data === true;
}
