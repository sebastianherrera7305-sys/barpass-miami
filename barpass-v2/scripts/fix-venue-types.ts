/**
 * Re-classifies venue `type` from Google's primaryType + alcohol signals, and
 * excludes rows that are not nightlife at all.
 *
 *   npm run fix:types -- --city="Gainesville" [--dry-run] [--all]
 */
import { createClient } from "@supabase/supabase-js";
// @ts-expect-error — 'ws' ships no types, same as the other scripts.
import ws from "ws";
import { classify, type TypeSignals } from "./venue-type-rules";

const PLACES_API_KEY = process.env.GOOGLE_PLACES_API_KEY;
const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!PLACES_API_KEY || !SUPABASE_URL || !SERVICE_ROLE_KEY) {
  console.error("Faltan env vars: GOOGLE_PLACES_API_KEY, NEXT_PUBLIC_SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY");
  process.exit(1);
}
const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  realtime: { transport: ws as unknown as typeof WebSocket },
});
const args = process.argv.slice(2);
const dryRun = args.includes("--dry-run");
const all = args.includes("--all");
const city = args.find((a) => a.startsWith("--city="))?.replace("--city=", "");
if (!city && !all) {
  console.error('Falta --city="Gainesville" (o --all)');
  process.exit(1);
}

async function signals(placeId: string): Promise<TypeSignals | null> {
  const res = await fetch(`https://places.googleapis.com/v1/places/${placeId}`, {
    headers: {
      "X-Goog-Api-Key": PLACES_API_KEY!,
      "X-Goog-FieldMask": "primaryType,types,servesBeer,servesWine,servesCocktails",
    },
  });
  if (!res.ok) return null;
  return (await res.json()) as TypeSignals;
}

async function main() {
  let q = supabase.from("venues").select("id,name,type,city,google_place_id").not("google_place_id", "is", null);
  if (city) q = q.eq("city", city);
  const { data: rows, error } = await q;
  if (error) throw new Error(error.message);
  console.log(`${rows?.length ?? 0} venues to re-classify${city ? ` in ${city}` : ""}\n`);

  let retyped = 0, excluded = 0, unchanged = 0, failed = 0;
  for (const v of rows ?? []) {
    const s = await signals(v.google_place_id as string);
    if (!s) { failed++; continue; }
    const { kind, reason } = classify(s);

    if (kind === null) {
      console.log(`  [fuera]   ${v.name} — ${reason}`);
      if (!dryRun) {
        const { error: e } = await supabase.from("venues")
          .update({ excluded_reason: "not_nightlife" }).eq("id", v.id);
        if (e) { console.error(`    ERROR: ${e.message}`); failed++; continue; }
      }
      excluded++;
    } else if (kind !== v.type) {
      console.log(`  [tipo]    ${v.name} — ${v.type} -> ${kind}  (${reason})`);
      if (!dryRun) {
        const { error: e } = await supabase.from("venues").update({ type: kind }).eq("id", v.id);
        if (e) { console.error(`    ERROR: ${e.message}`); failed++; continue; }
      }
      retyped++;
    } else {
      unchanged++;
    }
    await new Promise((r) => setTimeout(r, 80));
  }
  console.log(`\n${dryRun ? "[DRY RUN] " : ""}re-tipados: ${retyped}   excluidos: ${excluded}   sin cambio: ${unchanged}   fallaron: ${failed}`);
}

main();
