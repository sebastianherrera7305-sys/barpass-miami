/**
 * Checks whether The Grid's pg_cron job (refresh_grid_pulses, every 5 min —
 * see supabase/grid_cron.sql) is actually still running, using the
 * heartbeat row it now writes on every run (supabase/grid_cron_heartbeat.sql).
 * grid_pulses itself can't answer this: an empty table is indistinguishable
 * from "nobody's checked in anywhere right now" (normal) vs. "this hasn't
 * run in days" (broken) — pg_cron silently stopping (extension disabled, a
 * migration wipes the job, the project pauses/resumes) had zero signal
 * anywhere before this.
 *
 * Usage: npm run check:grid-health
 * Exits non-zero if stale, so this can gate a scheduled task/CI check later
 * without needing a real alerting pipeline built yet.
 */
import { createClient } from "@supabase/supabase-js";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
// pg_cron runs every 5 minutes — 3x that gives real room for jitter/a
// slow run without flagging a false positive on every tiny delay.
const STALE_AFTER_MINUTES = 15;

if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
  console.error("Faltan env vars: NEXT_PUBLIC_SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY");
  process.exit(1);
}

async function main() {
  const supabase = createClient(SUPABASE_URL!, SERVICE_ROLE_KEY!);
  const { data, error } = await supabase
    .from("cron_heartbeats")
    .select("job_name, last_run_at")
    .eq("job_name", "refresh-grid-pulses")
    .maybeSingle();

  if (error) {
    // Most likely cause: grid_cron_heartbeat.sql hasn't been run in
    // Supabase yet, so the table doesn't exist.
    console.error("ERROR consultando cron_heartbeats:", error.message);
    process.exit(1);
  }

  if (!data) {
    console.log("SIN DATOS: cron_heartbeats no tiene fila para refresh-grid-pulses todavía — ¿se corrió grid_cron_heartbeat.sql?");
    process.exit(1);
  }

  const lastRun = new Date(data.last_run_at);
  const minutesAgo = (Date.now() - lastRun.getTime()) / 60_000;

  if (minutesAgo > STALE_AFTER_MINUTES) {
    console.log(`STALE: The Grid no corrió hace ${minutesAgo.toFixed(1)} minutos (último: ${lastRun.toISOString()}). Revisar pg_cron en Supabase.`);
    process.exit(1);
  }

  console.log(`OK: The Grid corrió hace ${minutesAgo.toFixed(1)} minutos (último: ${lastRun.toISOString()}).`);
}

main();
