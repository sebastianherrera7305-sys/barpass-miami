import { createClient as createServiceClient } from "@supabase/supabase-js";

/**
 * Rate limiting sin dependencia externa — usa la función RPC
 * check_rate_limit (supabase/rate_limits_schema.sql), que hace un upsert
 * atómico por ventana de tiempo, mismo patrón que adjust_wallet_balance.
 *
 * Fail-open a propósito: si Supabase no está configurado o el RPC falla,
 * NO bloqueamos la request. Un rate limiter roto no debe tumbar pagos
 * reales — es una red de seguridad, no el camino crítico.
 */
export async function checkRateLimit(
  key: string,
  { maxRequests, windowSeconds }: { maxRequests: number; windowSeconds: number },
): Promise<boolean> {
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!supabaseUrl || !serviceRoleKey) return true;

  const supabase = createServiceClient(supabaseUrl, serviceRoleKey);
  const { data, error } = await supabase.rpc("check_rate_limit", {
    p_key: key,
    p_max_requests: maxRequests,
    p_window_seconds: windowSeconds,
  });
  if (error) return true;
  return data === true;
}
