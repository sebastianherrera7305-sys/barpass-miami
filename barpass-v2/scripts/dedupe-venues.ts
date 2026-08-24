/**
 * Finds and merges duplicate venues (same city + same normalized name)
 * across the whole `venues` table — not just the cities touched by the
 * Kimi age-bracket work. Same normalize() logic as
 * scripts/kimi-handoff/load-age-brackets.ts (case/emoji/&-vs-and
 * tolerant), so it also catches everything that loader's matching now
 * catches, applied retroactively to the ~1,817-venue original seed.
 *
 * Keep policy: within a duplicate group, keep the row with the highest
 * review_count (the more real, more-synced Google listing); tie-break by
 * older created_at (closer to the original seed). Never invents which
 * one is "correct" beyond that — just picks the more-established record.
 *
 * Before deleting a duplicate: migrates any venue_age_brackets tags it
 * has to the kept venue (upsert, so a real conflict on the same bracket
 * just keeps whichever tag was already there).
 *
 * Usage:
 *   node --env-file=.env.local --import tsx scripts/dedupe-venues.ts           # dry run, no writes
 *   node --env-file=.env.local --import tsx scripts/dedupe-venues.ts --apply   # actually delete
 */
import { createClient } from "@supabase/supabase-js";
// @ts-expect-error - ws no trae tipos propios
import ws from "ws";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
  console.error("Faltan env vars");
  process.exit(1);
}
const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  realtime: { transport: ws as unknown as typeof WebSocket },
});

function normalize(name: string): string {
  return name
    .toLowerCase()
    .replace(/&/g, " and ")
    .replace(/[^\p{L}\p{N}\s]/gu, "")
    .replace(/\s+/g, " ")
    .trim();
}

type Venue = { id: string; name: string; city: string; review_count: number; created_at: string };

async function fetchAllVenues(): Promise<Venue[]> {
  const all: Venue[] = [];
  let from = 0;
  const step = 1000;
  while (true) {
    const { data, error } = await supabase
      .from("venues")
      .select("id,name,city,review_count,created_at")
      .range(from, from + step - 1);
    if (error) throw error;
    if (!data || data.length === 0) break;
    all.push(...(data as Venue[]));
    if (data.length < step) break;
    from += step;
  }
  return all;
}

async function main() {
  const apply = process.argv.includes("--apply");
  const venues = await fetchAllVenues();
  console.log(`Total venues: ${venues.length}`);

  const groups = new Map<string, Venue[]>();
  for (const v of venues) {
    const key = `${v.city}::${normalize(v.name)}`;
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key)!.push(v);
  }

  const dupGroups = [...groups.values()].filter((g) => g.length > 1);
  console.log(`Grupos duplicados: ${dupGroups.length}`);

  let totalToRemove = 0;
  const byCity = new Map<string, number>();

  for (const group of dupGroups) {
    const sorted = [...group].sort((a, b) => {
      if (b.review_count !== a.review_count) return b.review_count - a.review_count;
      return new Date(a.created_at).getTime() - new Date(b.created_at).getTime();
    });
    const [keep, ...remove] = sorted;
    totalToRemove += remove.length;
    byCity.set(keep.city, (byCity.get(keep.city) ?? 0) + remove.length);

    console.log(`\n[${keep.city}] "${keep.name}" — quedan ${sorted.length}, se borran ${remove.length}`);
    console.log(`  KEEP: ${keep.id} (${keep.review_count} reviews, ${keep.created_at})`);
    for (const r of remove) {
      console.log(`  ${apply ? "DELETE" : "would delete"}: ${r.id} "${r.name}" (${r.review_count} reviews, ${r.created_at})`);
      if (apply) {
        const { data: tags } = await supabase
          .from("venue_age_brackets")
          .select("bracket,why,source")
          .eq("venue_id", r.id);
        for (const t of tags ?? []) {
          await supabase
            .from("venue_age_brackets")
            .upsert({ venue_id: keep.id, bracket: t.bracket, why: t.why, source: t.source }, { onConflict: "venue_id,bracket" });
        }
        await supabase.from("venues").delete().eq("id", r.id);
      }
    }
  }

  console.log(`\n${apply ? "BORRADOS" : "A BORRAR (dry run)"}: ${totalToRemove} venues duplicados`);
  console.log("Por ciudad:", Object.fromEntries(byCity));
  if (!apply) console.log("\nEsto fue un dry run. Corré de nuevo con --apply para ejecutar de verdad.");
}

main();
