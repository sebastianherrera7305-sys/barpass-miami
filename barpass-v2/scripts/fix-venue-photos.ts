/**
 * Re-resolves venue photos that were stored as a Google Places *media* URL.
 *
 * Two things were wrong with those rows, found 2026-09-13 after the TestFlight
 * report "No muestro ninguna foto en el venue":
 *
 *  1. They 400. A Places photo resource name is short-lived; Google answers
 *     "The photo resource in the request is invalid" once it ages out. 42 rows
 *     had rotted this way, 10 of them in Gainesville, which is where the
 *     report came from.
 *  2. They embedded GOOGLE_PLACES_API_KEY in the URL — and venues.image_url is
 *     world-readable through the anon key. A billable key was sitting in a
 *     public column.
 *
 * The 1,728 healthy rows hold a resolved lh3.googleusercontent.com URL, which
 * carries no key and does not expire. This brings the rest to that shape:
 * ask Place Details for a current photo name, resolve it with
 * skipHttpRedirect=true (which returns the CDN photoUri instead of a 302),
 * and store that.
 *
 *   npm run fix:photos -- [--dry-run]
 */
import { createClient } from "@supabase/supabase-js";
// @ts-expect-error — 'ws' ships no types, same as the other scripts.
import ws from "ws";

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
const dryRun = process.argv.includes("--dry-run");

/** Current photo name for a place, or null if Google has none. */
async function currentPhotoName(placeId: string): Promise<string | null> {
  const res = await fetch(`https://places.googleapis.com/v1/places/${placeId}`, {
    headers: { "X-Goog-Api-Key": PLACES_API_KEY!, "X-Goog-FieldMask": "photos" },
  });
  if (!res.ok) return null;
  const data = (await res.json()) as { photos?: { name: string }[] };
  return data.photos?.[0]?.name ?? null;
}

/** Resolve a photo name to the keyless CDN URL we can safely store. */
async function resolvePhotoUri(photoName: string): Promise<string | null> {
  const res = await fetch(
    `https://places.googleapis.com/v1/${photoName}/media?maxWidthPx=1200&skipHttpRedirect=true`,
    { headers: { "X-Goog-Api-Key": PLACES_API_KEY! } },
  );
  if (!res.ok) return null;
  const data = (await res.json()) as { photoUri?: string };
  const uri = data.photoUri ?? null;
  // Never store anything that still carries a key.
  return uri && !uri.includes("key=") ? uri : null;
}

async function main() {
  const { data: rows, error } = await supabase
    .from("venues")
    .select("id,name,city,google_place_id,image_url")
    .like("image_url", "%places.googleapis.com%");
  if (error) throw new Error(error.message);

  console.log(`${rows?.length ?? 0} venues holding a key-bearing / expiring photo URL\n`);
  let fixed = 0, cleared = 0, failed = 0;

  for (const v of rows ?? []) {
    if (!v.google_place_id) {
      console.log(`  [sin place_id] ${v.name} (${v.city})`);
      failed++;
      continue;
    }
    const photoName = await currentPhotoName(v.google_place_id);
    const uri = photoName ? await resolvePhotoUri(photoName) : null;

    if (!uri) {
      // Google genuinely has no usable photo. null is the honest value; a
      // broken URL renders as an empty grey card, which is worse.
      console.log(`  [sin foto]     ${v.name} (${v.city}) — image_url -> null`);
      if (!dryRun) {
        const { error: e } = await supabase.from("venues").update({ image_url: null }).eq("id", v.id);
        if (e) { console.error(`    ERROR: ${e.message}`); failed++; continue; }
      }
      cleared++;
    } else {
      console.log(`  [ok]           ${v.name} (${v.city})`);
      if (!dryRun) {
        const { error: e } = await supabase.from("venues").update({ image_url: uri }).eq("id", v.id);
        if (e) { console.error(`    ERROR: ${e.message}`); failed++; continue; }
      }
      fixed++;
    }
    await new Promise((r) => setTimeout(r, 200));
  }

  console.log(`\n${dryRun ? "[DRY RUN] " : ""}re-resolved: ${fixed}   sin foto real: ${cleared}   fallaron: ${failed}`);
}

main();
