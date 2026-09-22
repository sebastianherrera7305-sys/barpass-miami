/**
 * ⚠ REEMPLAZADO POR `refresh-venue-from-google.ts` (2026-09-14).
 *
 * Este script ya tuvo la idea correcta —una sola llamada por venue— pero con
 * un field mask más angosto: no trae priceLevel ni las señales de tipo, así
 * que después había que correr `fix-price-tiers.ts` y `fix-venue-types.ts`
 * encima, y cada uno pagaba su propio request. La pasada única cierra eso.
 *
 * No se borra: su manejo de `field_sources` (nunca pisar una procedencia
 * `manual_research`) es la referencia de cómo se escribe provenance.
 *
 * ---
 *
 * Re-pulls the core columns a venue card needs from Google Place Details, in
 * ONE request per venue, and records where each value came from.
 *
 * WHY THIS EXISTS (2026-09-15, Gainesville college-market audit)
 * 23 of the 119 served Gainesville venues were missing hours, rating,
 * review_count or a photo. Probing their `google_place_id` showed Google
 * *does* publish hours for 16 of them right now — Piesanos, Tela, Gumby's,
 * Boca Fiesta, Palomino, Hippodrome and the rest. The rows were simply stale:
 * `backfill-venue-hours.ts` ran on 2026-09-01 and those venues were added (or
 * their listing was filled in) afterwards. Nothing was broken in the data,
 * only old — and there was no single script that refreshed hours + rating +
 * review_count + photo together, so each re-check cost several Places calls
 * per venue across three scripts.
 *
 * RULES IT OBEYS
 *  - Only writes a field Google actually returned. A venue Google has no
 *    hours for keeps `hours = null`; an empty value is a fact, a guessed one
 *    is a lie (see the fabricated `music_genres` incident of 2026-09-01).
 *  - Never overwrites a non-null `website` / `phone` / `image_url` — those may
 *    have been researched by hand from the venue's own site. hours / rating /
 *    review_count / business_status ARE refreshed, because Google is their
 *    source of record and a stale rating is worse than a new one.
 *  - Updates by id, never by name. Names repeat within a city: 1702 W
 *    University Ave alone holds four different businesses.
 *  - Photos are stored in the resolved, key-free, pre-sized googleusercontent
 *    form — the same shape `fix-venue-photos.ts` settled on. A URL carrying
 *    `key=` must never land in `venues.image_url`, which anon can read.
 *  - Provenance goes in `field_sources.<column>` as
 *    {source, method, url, fetched_at}, overwriting any previous
 *    google_places claim for that column (it is the same source re-read) but
 *    never a `manual_research` one.
 *
 *   npx tsx scripts/refresh-venue-core-data.ts --city=Gainesville --dry-run
 *   npm run refresh:core -- --city=Gainesville --only-missing
 */
import { createClient } from "@supabase/supabase-js";
// @ts-expect-error — 'ws' ships no types, same as the other scripts.
import ws from "ws";
import { photoUri, placeDetailsUrl, placesClient, unwrap } from "./lib/places-calls";
import { warnSuperseded } from "./lib/superseded";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
  console.error("Faltan env vars: NEXT_PUBLIC_SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY");
  process.exit(1);
}

warnSuperseded({
  script: "refresh-venue-core-data.ts",
  replacement: "refresh-venue-from-google.ts",
  why: "Su field mask no trae priceLevel ni el tipo, así que obliga a una segunda pasada.",
});

// Sin PLACES_SPEND=1 no se toca la red: informa el costo estimado y sale.
const places = placesClient("refresh-venue-core-data");
const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  realtime: { transport: ws as unknown as typeof WebSocket },
});

const args = process.argv.slice(2);
const dryRun = args.includes("--dry-run");
const onlyMissing = args.includes("--only-missing");
const city = args.find((a) => a.startsWith("--city="))?.slice("--city=".length);
const limitArg = args.find((a) => a.startsWith("--limit="))?.slice("--limit=".length);
const limit = limitArg ? parseInt(limitArg, 10) : Infinity;

const FIELD_MASK = [
  "id",
  "displayName",
  "businessStatus",
  "rating",
  "userRatingCount",
  "websiteUri",
  "nationalPhoneNumber",
  "regularOpeningHours.periods",
  "photos.name",
];

interface Period {
  open?: { day: number; hour: number; minute: number };
  close?: { day: number; hour: number; minute: number };
}
interface DayHours { day: number; open: string; close: string }

interface PlaceDetails {
  displayName?: { text?: string };
  businessStatus?: string;
  rating?: number;
  userRatingCount?: number;
  websiteUri?: string;
  nationalPhoneNumber?: string;
  regularOpeningHours?: { periods?: Period[] };
  photos?: { name: string }[];
}

interface Row {
  id: string;
  name: string;
  city: string | null;
  google_place_id: string | null;
  hours: DayHours[] | null;
  rating: number | null;
  review_count: number | null;
  image_url: string | null;
  website: string | null;
  phone: string | null;
  business_status: string | null;
  field_sources: Record<string, unknown> | null;
}

const hhmm = (h: number, m: number) => `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}`;

/** Google periods -> our shape, identical to backfill-venue-hours.ts. `day` is
 *  the day it OPENS (0 = Sunday); a close earlier than the open runs past
 *  midnight, which is the normal case for nightlife. A period with no close is
 *  Google's encoding for "open 24 hours" on that day. */
export function toWeeklyHours(periods: Period[] | undefined): DayHours[] | null {
  if (!periods?.length) return null;
  const out: DayHours[] = [];
  for (const p of periods) {
    if (!p.open) continue;
    if (!p.close) { out.push({ day: p.open.day, open: "00:00", close: "23:59" }); continue; }
    out.push({ day: p.open.day, open: hhmm(p.open.hour, p.open.minute), close: hhmm(p.close.hour, p.close.minute) });
  }
  return out.length ? out : null;
}

/** El reintento de red y 429/5xx —un fetch que revienta no puede terminar un
 *  run de miles— vive ahora en lib/places-calls.ts, junto con el medidor. */
async function googleJson<T>(placeId: string): Promise<T | null> {
  return unwrap<T>(() => places.placeDetails(placeId, FIELD_MASK), `core ${placeId}`);
}

/** Resolve a photo resource name to the keyless, pre-sized CDN URL. Anything
 *  still carrying `key=` is rejected rather than stored. */
async function resolvePhotoUri(photoName: string): Promise<string | null> {
  return photoUri(places, photoName);
}

function isMissingCore(r: Row): boolean {
  return !r.hours?.length || r.rating == null || r.review_count == null || !r.image_url;
}

async function main() {
  const rows: Row[] = [];
  for (let from = 0; ; from += 1000) {
    let q = supabase
      .from("venues")
      .select("id,name,city,google_place_id,hours,rating,review_count,image_url,website,phone,business_status,field_sources")
      .not("google_place_id", "is", null)
      .is("excluded_reason", null)
      .or("business_status.is.null,business_status.neq.CLOSED_PERMANENTLY")
      .order("name")
      .range(from, from + 999);
    if (city) q = q.eq("city", city);
    const { data, error } = await q;
    if (error) throw new Error(error.message);
    rows.push(...((data ?? []) as Row[]));
    if ((data?.length ?? 0) < 1000) break;
  }

  const targets = onlyMissing ? rows.filter(isMissingCore) : rows;
  console.log(
    `${targets.length} venues${city ? ` in ${city}` : ""}${onlyMissing ? " missing core data" : ""}` +
      `${dryRun ? " (dry run)" : ""}\n`,
  );

  const fetchedAt = new Date().toISOString();
  const tally: Record<string, number> = {};
  let processed = 0, touched = 0, noHours = 0, failed = 0;

  for (const v of targets) {
    if (processed >= limit) break;
    processed++;

    // El URL se arma con el helper del cliente: acá sólo se guarda como
    // procedencia en field_sources, no se le pega.
    const url = placeDetailsUrl(v.google_place_id as string);
    const g = await googleJson<PlaceDetails>(v.google_place_id as string);
    if (!g) { console.warn(`  [places falló] ${v.name}`); failed++; continue; }

    const patch: Record<string, unknown> = {};
    const sources: Record<string, unknown> = { ...(v.field_sources ?? {}) };
    const note = (field: string) => {
      const prior = sources[field] as { source?: string } | undefined;
      // A hand-researched value's provenance is never replaced by this run.
      if (prior?.source === "manual_research") return;
      sources[field] = { source: "google_places", method: "places_api_v1_place_details", url, fetched_at: fetchedAt };
      tally[field] = (tally[field] ?? 0) + 1;
    };

    const hours = toWeeklyHours(g.regularOpeningHours?.periods);
    if (hours) {
      if (JSON.stringify(hours) !== JSON.stringify(v.hours)) { patch.hours = hours; note("hours"); }
    } else if (!v.hours?.length) {
      noHours++;
    }

    if (typeof g.rating === "number" && g.rating !== v.rating) { patch.rating = g.rating; note("rating"); }
    if (typeof g.userRatingCount === "number" && g.userRatingCount !== v.review_count) {
      patch.review_count = g.userRatingCount; note("review_count");
    }
    if (g.businessStatus && g.businessStatus !== v.business_status) patch.business_status = g.businessStatus;

    // Only ever fills a hole here — a researched website/phone outranks Google's.
    if (!v.website && g.websiteUri) { patch.website = g.websiteUri; note("website"); }
    if (!v.phone && g.nationalPhoneNumber) { patch.phone = g.nationalPhoneNumber; note("phone"); }

    if (!v.image_url && g.photos?.[0]?.name) {
      const uri = await resolvePhotoUri(g.photos[0].name);
      if (uri) { patch.image_url = uri; note("image_url"); }
    }

    if (Object.keys(patch).length === 0) continue;
    patch.field_sources = sources;
    patch.google_synced_at = fetchedAt;
    touched++;

    const changed = Object.keys(patch).filter((k) => k !== "field_sources" && k !== "google_synced_at");
    console.log(`  ${v.name} (${v.city ?? "?"}) → ${changed.join(", ")}`);

    if (!dryRun) {
      const { error } = await supabase.from("venues").update(patch).eq("id", v.id);
      if (error) { console.error(`    ERROR ${v.name}: ${error.message}`); failed++; touched--; }
    }
    await new Promise((r) => setTimeout(r, 60));
  }

  console.log(
    `\n${dryRun ? "[DRY RUN] " : ""}revisados: ${processed}   actualizados: ${touched}   ` +
      `sin horario en Google: ${noHours}   fallaron: ${failed}`,
  );
  for (const [field, count] of Object.entries(tally).sort((a, b) => b[1] - a[1])) {
    console.log(`   ${field.padEnd(14)} ${count}`);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
