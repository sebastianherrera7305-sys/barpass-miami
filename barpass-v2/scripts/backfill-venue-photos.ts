/**
 * Gives every venue a real photo, and a photo that is light enough to load.
 *
 * TWO PROBLEMS, ONE CAUSE
 * 167 of the 1814 served venues never went through Google Places enrichment.
 * They are *exactly* the same 167 that have no photo, the same 167 whose
 * open_time is the placeholder "Ver Google Maps", and the same 167 with no
 * price_tier — and zero enriched venues have broken hours. So this one job
 * fixes photos, hours and price level together.
 *
 * WHY THE URL FORM MATTERS
 * Three forms of Places photo URL exist and only one is right here:
 *
 *   1. `…/photos/{ref}`                     — what is stored today. Key-free
 *      (good: `venues` is publicly readable) but ignores every sizing
 *      parameter and always redirects to the full original: 1.3 MB per card.
 *      That is the "no carga rápido" complaint.
 *   2. `…/photos/{ref}/media?maxWidthPx=400&key=…` — sized (42 KB) but embeds
 *      the API key in a row anyone can read. Never store this.
 *   3. `…/media?maxWidthPx=…&skipHttpRedirect=true` → returns JSON with a
 *      `photoUri` that is BOTH sized AND key-free. This is what we store.
 *
 * The photoUri is a resolved googleusercontent link; Google does not promise
 * it is permanent. `google_place_id` is kept on every row, so this script can
 * always regenerate. If photos ever start 404ing, re-run it.
 *
 * COST: this spends real Google Places quota — roughly one search + one
 * details + one photo call per missing venue. Run with --dry-run first.
 *
 * Usage:
 *   npx tsx scripts/backfill-venue-photos.ts --dry-run
 *   npx tsx scripts/backfill-venue-photos.ts --limit 20
 *   npx tsx scripts/backfill-venue-photos.ts
 */

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const PLACES_KEY = process.env.GOOGLE_PLACES_API_KEY;

if (!SUPABASE_URL || !SERVICE_KEY) throw new Error("Missing Supabase env vars");
if (!PLACES_KEY) throw new Error("Missing GOOGLE_PLACES_API_KEY");

const DRY_RUN = process.argv.includes("--dry-run");
/**
 * --gaps re-visits rows that already have a photo but are still missing hours
 * or price. The first pass only selected `image_url is null`, so 324 of the
 * 331 rows with no price_tier were never looked at.
 */
const GAPS = process.argv.includes("--gaps");
const LIMIT = (() => {
  const i = process.argv.indexOf("--limit");
  return i >= 0 ? Number(process.argv[i + 1]) : Infinity;
})();

/** Cards render ~280pt wide at 3x. 800px covers that and the list thumbnails. */
const PHOTO_WIDTH = 800;

/**
 * Plain PostgREST over fetch rather than supabase-js: the client pulls in
 * realtime, which throws on Node 20 for want of a native WebSocket. This
 * script needs two verbs and no realtime.
 */
const REST = {
  headers: {
    apikey: SERVICE_KEY!,
    Authorization: `Bearer ${SERVICE_KEY}`,
    "Content-Type": "application/json",
  },
  async select(query: string): Promise<unknown[]> {
    const res = await fetch(`${SUPABASE_URL}/rest/v1/venues?${query}`, { headers: this.headers });
    if (!res.ok) throw new Error(`select ${res.status}: ${await res.text()}`);
    return res.json();
  },
  async update(id: string, patch: Record<string, unknown>): Promise<string | null> {
    const res = await fetch(`${SUPABASE_URL}/rest/v1/venues?id=eq.${id}`, {
      method: "PATCH",
      headers: { ...this.headers, Prefer: "return=minimal" },
      body: JSON.stringify(patch),
    });
    return res.ok ? null : `${res.status}: ${(await res.text()).slice(0, 120)}`;
  },
};

interface Venue {
  id: string;
  name: string;
  city: string;
  address: string | null;
  google_place_id: string | null;
  image_url: string | null;
  open_time: string | null;
  price_tier: number | null;
}

/** "22:30" is usable; "Ver Google Maps" and "Friday: 5:00 PM – 2:00 AM" are not. */
function hoursAreParseable(value: string | null): boolean {
  if (!value) return false;
  const [h, m] = value.split(":");
  return Number.isFinite(Number(h)) && Number.isFinite(Number(m));
}

async function places<T>(url: string, init?: RequestInit): Promise<T | null> {
  const res = await fetch(url, init);
  if (!res.ok) {
    console.warn(`   places ${res.status}: ${(await res.text()).slice(0, 120)}`);
    return null;
  }
  return (await res.json()) as T;
}

async function findPlaceId(v: Venue): Promise<string | null> {
  const query = [v.name, v.address, v.city].filter(Boolean).join(", ");
  const data = await places<{ places?: { id: string }[] }>(
    "https://places.googleapis.com/v1/places:searchText",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": PLACES_KEY!,
        "X-Goog-FieldMask": "places.id",
      },
      body: JSON.stringify({ textQuery: query, maxResultCount: 1 }),
    },
  );
  return data?.places?.[0]?.id ?? null;
}

interface Details {
  photos?: { name: string }[];
  regularOpeningHours?: { periods?: { open?: { hour: number; minute: number }; close?: { hour: number; minute: number } }[] };
  priceLevel?: string;
  businessStatus?: string;
}

async function getDetails(placeId: string): Promise<Details | null> {
  return places<Details>(`https://places.googleapis.com/v1/places/${placeId}`, {
    headers: {
      "X-Goog-Api-Key": PLACES_KEY!,
      "X-Goog-FieldMask": "photos,regularOpeningHours,priceLevel,businessStatus",
    },
  });
}

/**
 * The key-free, pre-sized URL — see the header comment for why this specific
 * call shape is the only acceptable one.
 */
async function sizedPhotoUrl(photoName: string): Promise<string | null> {
  const data = await places<{ photoUri?: string }>(
    `https://places.googleapis.com/v1/${photoName}/media` +
      `?maxWidthPx=${PHOTO_WIDTH}&skipHttpRedirect=true&key=${PLACES_KEY}`,
  );
  const uri = data?.photoUri ?? null;
  // Belt and braces: never persist a URL carrying the key, whatever Google returns.
  if (uri && (uri.includes("key=") || uri.includes("AIza"))) {
    console.warn("   refusing to store a photoUri containing an API key");
    return null;
  }
  return uri;
}

const PRICE_LEVELS: Record<string, number> = {
  PRICE_LEVEL_INEXPENSIVE: 1,
  PRICE_LEVEL_MODERATE: 2,
  PRICE_LEVEL_EXPENSIVE: 3,
  PRICE_LEVEL_VERY_EXPENSIVE: 4,
};

function pad(n: number): string {
  return String(n).padStart(2, "0");
}

async function main() {
  const all = (await REST.select(
    "select=id,name,city,address,google_place_id,image_url,open_time,price_tier" +
      "&excluded_reason=is.null&order=name",
  )) as Venue[];

  const needsSomething = (v: Venue) =>
    !v.image_url || !hoursAreParseable(v.open_time) || v.price_tier == null;
  const rows = all.filter(GAPS ? needsSomething : (v) => !v.image_url);
  const venues = rows.slice(0, LIMIT);
  console.log(
    `${venues.length} venues ${GAPS ? "missing a photo, hours or price" : "without a photo"}` +
      `${DRY_RUN ? " (dry run)" : ""}\n`,
  );

  let gotPhoto = 0, gotHours = 0, gotPrice = 0, noPlace = 0, noPhoto = 0;

  for (const [i, v] of venues.entries()) {
    const label = `[${i + 1}/${venues.length}] ${v.name.slice(0, 38)} — ${v.city}`;

    const placeId = v.google_place_id ?? (await findPlaceId(v));
    if (!placeId) {
      noPlace++;
      console.log(`${label}\n   no Google match`);
      continue;
    }

    const details = await getDetails(placeId);

    // Only spend a photo call when the row actually needs one, and walk the
    // whole array: Google occasionally returns a first entry that 404s.
    let photoUrl: string | null = null;
    if (!v.image_url) {
      for (const photo of details?.photos ?? []) {
        photoUrl = await sizedPhotoUrl(photo.name);
        if (photoUrl) break;
      }
    }

    const update: Record<string, unknown> = { google_place_id: placeId, google_synced_at: new Date().toISOString() };
    if (photoUrl) { update.image_url = photoUrl; gotPhoto++; } else if (!v.image_url) { noPhoto++; }

    // Only fill hours when the row has none usable — never overwrite good data.
    const period = details?.regularOpeningHours?.periods?.[0];
    if (!hoursAreParseable(v.open_time) && period?.open && period?.close) {
      update.open_time = `${pad(period.open.hour)}:${pad(period.open.minute)}`;
      update.close_time = `${pad(period.close.hour)}:${pad(period.close.minute)}`;
      gotHours++;
    }
    if (v.price_tier == null && details?.priceLevel && PRICE_LEVELS[details.priceLevel]) {
      update.price_tier = PRICE_LEVELS[details.priceLevel];
      gotPrice++;
    }
    if (details?.businessStatus && details.businessStatus !== "OPERATIONAL") {
      update.business_status = details.businessStatus;
    }

    console.log(`${label}\n   photo:${photoUrl ? "yes" : "NO"} hours:${update.open_time ?? "-"} price:${update.price_tier ?? "-"}`);

    if (!DRY_RUN) {
      const err = await REST.update(v.id, update);
      if (err) console.warn(`   update failed: ${err}`);
    }
  }

  console.log(
    `\nphotos:${gotPhoto}  hours:${gotHours}  price:${gotPrice}  ` +
      `no-google-match:${noPlace}  google-has-no-photo:${noPhoto}`,
  );
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
