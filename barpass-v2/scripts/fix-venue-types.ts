/**
 * ⚠ SU LLAMADA A GOOGLE QUEDÓ REEMPLAZADA POR `refresh-venue-from-google.ts`.
 *
 * Lo que este script pide (primaryType, types, servesBeer/Wine/Cocktails) son
 * campos Enterprise: de los más caros del catálogo de Places. La pasada única
 * los trae junto con horarios, rating, foto y precio en UN request por venue.
 * Pedirlos otra vez acá es pagar el nivel caro dos veces por el mismo venue.
 *
 * La clasificación tampoco es única ya: `venue-google-patch.ts` corre el mismo
 * `classify()` y el mismo manejo de `excluded_reason` (excluir, y deshacer una
 * exclusión anterior), con una guarda que este script NO tiene — si Google no
 * devuelve ni primaryType ni types, no toca la fila, en vez de dejar que
 * `classify({})` la excluya por una respuesta vacía.
 *
 * O sea: no hay razón para correr éste. Se conserva sólo como referencia de
 * dónde salió la regla.
 *
 * ---
 *
 * Re-classifies venue `type` from Google's primaryType + alcohol signals, and
 * excludes rows that are not nightlife at all.
 *
 *   npm run fix:types -- --city="Gainesville" [--dry-run] [--all]
 */
import { createClient } from "@supabase/supabase-js";
// @ts-expect-error — 'ws' ships no types, same as the other scripts.
import ws from "ws";
import { classify, type TypeSignals } from "./venue-type-rules";
import { placesClient, unwrap } from "./lib/places-calls";
import { warnSuperseded } from "./lib/superseded";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
  console.error("Faltan env vars: NEXT_PUBLIC_SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY");
  process.exit(1);
}

warnSuperseded({
  script: "fix-venue-types.ts",
  replacement: "refresh-venue-from-google.ts",
  why: "Esa pasada ya clasifica con las mismas señales, y con una guarda más contra excluir por respuesta vacía.",
});

// Sin PLACES_SPEND=1 no se toca la red: informa el costo estimado y sale.
const places = placesClient("fix-venue-types");
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

/** Un solo error de red mataba el run entero: 3.900 fetches seguidos sin
 *  catch. Ese endurecimiento —reintentar la red y 429/5xx, nunca un 4xx real—
 *  vive ahora en lib/places-calls.ts, donde además se cuenta lo que cuesta. */
async function signals(placeId: string): Promise<TypeSignals | null> {
  return unwrap<TypeSignals>(
    () =>
      places.placeDetails(placeId, [
        "primaryType",
        "types",
        "servesBeer",
        "servesWine",
        "servesCocktails",
      ]),
    `types ${placeId}`,
  );
}

async function main() {
  // PostgREST caps every response at 1000 rows. A bare select silently
  // processed the first 999 of 3,919 and reported success — the same cap that
  // made add-venues.ts "discover" venues it already had. Page explicitly.
  const rows: { id: string; name: string; type: string; city: string | null; google_place_id: string; hours: { day: number; open: string; close: string }[] | null; excluded_reason: string | null }[] = [];
  for (let from = 0; ; from += 1000) {
    let q = supabase.from("venues").select("id,name,type,city,google_place_id,hours,excluded_reason")
      .not("google_place_id", "is", null).range(from, from + 999);
    if (city) q = q.eq("city", city);
    const { data, error } = await q;
    if (error) throw new Error(error.message);
    rows.push(...((data ?? []) as typeof rows));
    if ((data?.length ?? 0) < 1000) break;
  }
  console.log(`${rows.length} venues to re-classify${city ? ` in ${city}` : ""}\n`);

  let retyped = 0, excluded = 0, unchanged = 0, failed = 0, restored = 0;
  for (const v of rows) {
    const s = await signals(v.google_place_id as string);
    if (!s) { failed++; continue; }
    const { kind, reason } = classify({ ...s, hours: v.hours });

    if (kind === "unknown") {
      // Google told us nothing. Keep the row exactly as it is — and if a
      // previous pass excluded it on this same silence, undo that.
      if (v.excluded_reason === "not_nightlife") {
        console.log(`  [de vuelta] ${v.name} — ${reason}`);
        if (!dryRun) {
          const { error: e } = await supabase.from("venues")
            .update({ excluded_reason: null }).eq("id", v.id);
          if (e) { console.error(`    ERROR: ${e.message}`); failed++; continue; }
        }
        restored++;
      } else {
        unchanged++;
      }
    } else if (kind === null && SPECIFIC_NIGHTLIFE.has(v.type as string)) {
      // Positively not a venue by Google — but the catalogue already types it
      // as real nightlife, which is the stronger claim. Leave it and say so.
      console.log(`  [conservado] ${v.name} (${v.type}) — Google dice "${reason}", se respeta el tipo existente`);
      unchanged++;
    } else if (kind === null) {
      console.log(`  [fuera]   ${v.name} — ${reason}`);
      if (!dryRun) {
        const { error: e } = await supabase.from("venues")
          .update({ excluded_reason: "not_nightlife" }).eq("id", v.id);
        if (e) { console.error(`    ERROR: ${e.message}`); failed++; continue; }
      }
      excluded++;
    } else if (v.excluded_reason === "not_nightlife") {
      // A previous pass excluded it on its label alone. It now classifies as a
      // venue, so put it back — an exclusion this script made must be one this
      // script can undo, or a bad rule is permanent.
      console.log(`  [de vuelta] ${v.name} — ${reason}`);
      if (!dryRun) {
        const { error: e } = await supabase.from("venues")
          .update({ excluded_reason: null, type: kind }).eq("id", v.id);
        if (e) { console.error(`    ERROR: ${e.message}`); failed++; continue; }
      }
      restored++;
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
  console.log(`\n${dryRun ? "[DRY RUN] " : ""}re-tipados: ${retyped}   excluidos: ${excluded}   restaurados: ${restored}   sin cambio: ${unchanged}   fallaron: ${failed}`);
}

main();
