/**
 * Sets avg_spend to NULL for every venue that carries the fake `0` default
 * from scripts/add-venues.ts (`avg_spend: 0` literal on insert — Google
 * Places has no reliable average-spend-in-dollars field, so this was never
 * a real per-venue number).
 *
 * Requires supabase/avg_spend_allow_null.sql to have been run first (in the
 * Supabase SQL editor) — the column is `not null default 0` until then, so
 * this UPDATE will fail with a not-null violation if run too early.
 *
 * Deliberately narrow: only touches rows where avg_spend = 0. The 175 rows
 * with a non-zero avg_spend (all Miami, all inserted in the same
 * 2026-07-07 03:08–03:10 batch, all sharing an identical
 * music_genres/vibes/dress_code/parking/best_arrival_time/peak_hours/
 * popular_drinks block regardless of venue type) are LEFT UNTOUCHED here on
 * explicit instruction, even though the audit found strong evidence they
 * are the same kind of fabricated seed data, not real per-venue figures —
 * flagged for a human decision rather than silently changed.
 *
 * Uso: npm run fix-avg-spend [-- --dry-run]
 */
import { createClient } from "@supabase/supabase-js";
// @ts-expect-error — 'ws' no trae tipos propios, ver enrich-venues.ts
import ws from "ws";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
  console.error("Faltan env vars: NEXT_PUBLIC_SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY");
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  realtime: { transport: ws as unknown as typeof WebSocket },
});

const dryRun = process.argv.includes("--dry-run");

async function fetchZeroSpendIds(): Promise<string[]> {
  const all: string[] = [];
  const pageSize = 1000;
  let offset = 0;
  for (;;) {
    const { data, error } = await supabase
      .from("venues")
      .select("id")
      .eq("avg_spend", 0)
      .order("id")
      .range(offset, offset + pageSize - 1);
    if (error) {
      console.error("No se pudieron leer los venues:", error.message);
      process.exit(1);
    }
    if (!data || data.length === 0) break;
    all.push(...data.map((r) => r.id as string));
    if (data.length < pageSize) break;
    offset += pageSize;
  }
  return all;
}

async function main() {
  const ids = await fetchZeroSpendIds();
  console.log(`${ids.length} venues con avg_spend=0 (fake default) encontrados.`);

  if (dryRun) {
    console.log("[DRY RUN] no se escribe nada.");
    return;
  }

  let ok = 0;
  let errors = 0;
  const chunkSize = 500;
  for (let i = 0; i < ids.length; i += chunkSize) {
    const chunk = ids.slice(i, i + chunkSize);
    const { error } = await supabase.from("venues").update({ avg_spend: null }).in("id", chunk);
    if (error) {
      console.error(`ERROR actualizando chunk ${i}-${i + chunk.length}: ${error.message}`);
      errors += chunk.length;
    } else {
      ok += chunk.length;
      console.log(`  actualizados ${ok}/${ids.length}`);
    }
  }

  console.log(`\nListo. ok=${ok} errors=${errors}`);
}

main();
