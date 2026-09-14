/**
 * Removes rows that are the SAME business listed twice, not chains.
 *
 * Google sometimes carries two place records for one venue (an old listing and
 * a claimed one). Those arrive as two rows with the same name and the SAME
 * street address — MacDinton's GNV, Ford's Garage and Lillian's Music Store all
 * appeared twice in Gainesville on 2026-09-13, which a user reads as the
 * catalogue being sloppy.
 *
 * Address equality is the whole test, deliberately. Three Sonny's BBQ and three
 * QDOBA in one city are REAL, separate locations and must survive; an earlier
 * name-only dedupe wrongly excluded three legitimate Miller's Ale House rows.
 * The survivor is the row with more reviews (the listing people actually use);
 * the other is excluded, never deleted, so the decision stays auditable.
 *
 *   npm run dedupe:address -- [--dry-run]
 */
import { createClient } from "@supabase/supabase-js";
// @ts-expect-error — 'ws' ships no types, same as the other scripts.
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

const norm = (s: string | null) => (s ?? "").toLowerCase().replace(/[^a-z0-9]/g, "");

interface Row { id: string; name: string; city: string | null; address: string | null; review_count: number | null }

async function main() {
  const rows: Row[] = [];
  for (let from = 0; ; from += 1000) {
    const { data, error } = await supabase
      .from("venues").select("id,name,city,address,review_count")
      .is("excluded_reason", null).range(from, from + 999);
    if (error) throw new Error(error.message);
    rows.push(...((data ?? []) as Row[]));
    if ((data?.length ?? 0) < 1000) break;
  }

  const groups = new Map<string, Row[]>();
  for (const v of rows) {
    if (!v.address) continue;
    const key = `${norm(v.city)}|${norm(v.name)}|${norm(v.address)}`;
    groups.set(key, [...(groups.get(key) ?? []), v]);
  }

  let removed = 0;
  for (const dupes of groups.values()) {
    if (dupes.length < 2) continue;
    const sorted = [...dupes].sort((a, b) => (b.review_count ?? 0) - (a.review_count ?? 0));
    const [keep, ...drop] = sorted;
    console.log(`  ${keep.name} (${keep.city}) — keeping ${keep.review_count ?? 0} reviews, dropping ${drop.length}`);
    for (const d of drop) {
      if (!dryRun) {
        const { error } = await supabase.from("venues")
          .update({ excluded_reason: "duplicate_listing" }).eq("id", d.id);
        if (error) { console.error(`    ERROR: ${error.message}`); continue; }
      }
      removed++;
    }
  }
  console.log(`\n${dryRun ? "[DRY RUN] " : ""}duplicate rows excluded: ${removed}`);
}

main();
