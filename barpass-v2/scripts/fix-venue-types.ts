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
const SPECIFIC_NIGHTLIFE = new Set(["club", "rooftop", "lounge", "sports_bar", "brewery"]);

const city = args.find((a) => a.startsWith("--city="))?.replace("--city=", "");
if (!city && !all) {
  console.error('Falta --city="Gainesville" (o --all)');
  process.exit(1);
}

/** One transient network error used to kill the whole run: 3,900 sequential
 *  fetches and no catch, so a single blip threw and the process exited. Retry
 *  the network, never an actual HTTP answer from Google — a 404 means the place
 *  is gone and retrying it is just burning quota. */
async function signals(placeId: string, retries = 3): Promise<TypeSignals | null> {
  for (let attempt = 0; ; attempt++) {
    try {
      const res = await fetch(`https://places.googleapis.com/v1/places/${placeId}`, {
        headers: {
          "X-Goog-Api-Key": PLACES_API_KEY!,
          "X-Goog-FieldMask": "primaryType,types,servesBeer,servesWine,servesCocktails",
        },
      });
      if (res.status === 429 || res.status >= 500) {
        if (attempt >= retries) return null;
        await new Promise((r) => setTimeout(r, 1000 * 2 ** attempt));
        continue;
      }
      if (!res.ok) return null;
      return (await res.json()) as TypeSignals;
    } catch (err) {
      if (attempt >= retries) {
        console.error(`  red falló para ${placeId}: ${(err as Error).message}`);
        return null;
      }
      await new Promise((r) => setTimeout(r, 1000 * 2 ** attempt));
    }
  }
}

async function main() {
  // PostgREST caps every response at 1000 rows. A bare select silently
  // processed the first 999 of 3,919 and reported success — the same cap that
  // made add-venues.ts "discover" venues it already had. Page explicitly.
  const rows: { id: string; name: string; type: string; city: string | null; google_place_id: string; hours: { day: number; open: string; close: string }[] | null }[] = [];
  for (let from = 0; ; from += 1000) {
    let q = supabase.from("venues").select("id,name,type,city,google_place_id,hours")
      .not("google_place_id", "is", null).range(from, from + 999);
    if (city) q = q.eq("city", city);
    const { data, error } = await q;
    if (error) throw new Error(error.message);
    rows.push(...((data ?? []) as typeof rows));
    if ((data?.length ?? 0) < 1000) break;
  }
  console.log(`${rows.length} venues to re-classify${city ? ` in ${city}` : ""}\n`);

  let retyped = 0, excluded = 0, unchanged = 0, failed = 0;
  for (const v of rows) {
    const s = await signals(v.google_place_id as string);
    if (!s) { failed++; continue; }
    const { kind, reason } = classify({ ...s, hours: v.hours });

    if (kind === null) {
      console.log(`  [fuera]   ${v.name} — ${reason}`);
      if (!dryRun) {
        const { error: e } = await supabase.from("venues")
          .update({ excluded_reason: "not_nightlife" }).eq("id", v.id);
        if (e) { console.error(`    ERROR: ${e.message}`); failed++; continue; }
      }
      excluded++;
    } else if (kind === "bar" && SPECIFIC_NIGHTLIFE.has(v.type as string)) {
      // Google's primaryType is "bar" for plenty of rooftops, lounges and
      // sports bars. Whatever is already on the row is more specific and was
      // set deliberately; a generic "bar" is not new information, and
      // overwriting would re-rank the venue (club 18 / bar 15 / lounge 10 /
      // sports bar 6 in the going-out scorer).
      unchanged++;
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
