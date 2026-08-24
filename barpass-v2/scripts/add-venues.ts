/**
 * Descubre venues reales de vida nocturna en una ciudad nueva vía Google
 * Places (API New — Text Search + Place Details) y los inserta en Supabase.
 * Misma regla dura que enrich-venues.ts: si Google no lo confirma, no se
 * escribe. Nunca se inventa un venue, un horario, ni un dato.
 *
 * Uso:
 *   npm run add-venues -- --city="Gainesville, FL" [--dry-run] [--limit=20]
 *
 * Requiere en .env.local: GOOGLE_PLACES_API_KEY, NEXT_PUBLIC_SUPABASE_URL,
 * SUPABASE_SERVICE_ROLE_KEY.
 */
import { createClient } from "@supabase/supabase-js";
// @ts-expect-error — 'ws' no trae tipos propios, ver enrich-venues.ts.
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

const args = process.argv.slice(2);
const dryRun = args.includes("--dry-run");
const cityArg = args.find((a) => a.startsWith("--city="))?.replace("--city=", "");
const collegeArg = args.find((a) => a.startsWith("--college="))?.replace("--college=", "") ?? null;
// Sin --limit: cobertura real completa, no un tope artificial (pedido §1).
const limitArg = args.find((a) => a.startsWith("--limit="))?.replace("--limit=", "");
const limit = limitArg ? parseInt(limitArg, 10) : Infinity;

if (!cityArg) {
  console.error('Falta --city="Ciudad, ST" — ej: --city="Gainesville, FL" [--college="University of Florida"]');
  process.exit(1);
}

interface PlaceSummary {
  id: string;
  displayName?: { text: string };
  formattedAddress?: string;
  types?: string[];
}
interface SearchResponse {
  places?: PlaceSummary[];
}
interface PlaceDetails {
  id: string;
  displayName?: { text: string };
  formattedAddress?: string;
  location?: { latitude: number; longitude: number };
  nationalPhoneNumber?: string;
  websiteUri?: string;
  rating?: number;
  userRatingCount?: number;
  businessStatus?: string;
  types?: string[];
  regularOpeningHours?: { periods?: { open?: { hour: number; minute: number }; close?: { hour: number; minute: number } }[] };
  photos?: { name: string }[];
  priceLevel?: string;
  addressComponents?: { longText: string; types: string[] }[];
  accessibilityOptions?: { wheelchairAccessibleEntrance?: boolean };
  outdoorSeating?: boolean;
  goodForGroups?: boolean;
  goodForWatchingSports?: boolean;
  liveMusic?: boolean;
  reservable?: boolean;
  servesVegetarianFood?: boolean;
  restroom?: boolean;
}

/** Google type -> nuestro enum constreñido. null = no es un venue de nightlife real. */
function mapType(types: string[] | undefined): string | null {
  const t = new Set(types ?? []);
  if (t.has("night_club")) return "club";
  if (t.has("bar") || t.has("pub") || t.has("wine_bar")) return "bar";
  if (t.has("brewery") || t.has("bar_and_grill")) return "brewery";
  if (t.has("restaurant")) return "restaurant";
  return null;
}

const PRICE_LEVEL_MAP: Record<string, number> = {
  PRICE_LEVEL_FREE: 1,
  PRICE_LEVEL_INEXPENSIVE: 1,
  PRICE_LEVEL_MODERATE: 2,
  PRICE_LEVEL_EXPENSIVE: 3,
  PRICE_LEVEL_VERY_EXPENSIVE: 4,
};

function formatTime(h: number, m: number): string {
  return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}`;
}

// `timezone` is NOT NULL in the schema. A US state maps deterministically
// to an IANA zone (verifiable geography, not invented venue data) — Google
// Places doesn't return this field directly, so it's derived here instead
// of left null. AZ has no DST and DE/IN(-ish) are covered as encountered.
const STATE_TIMEZONE: Record<string, string> = {
  FL: "America/New_York", GA: "America/New_York", NC: "America/New_York",
  OH: "America/New_York", PA: "America/New_York", MI: "America/New_York",
  IN: "America/New_York", WV: "America/New_York", NY: "America/New_York",
  TN: "America/Chicago", LA: "America/Chicago", TX: "America/Chicago",
  WI: "America/Chicago", MS: "America/Chicago", IL: "America/Chicago",
  MO: "America/Chicago", KS: "America/Chicago", IA: "America/Chicago",
  AZ: "America/Phoenix", CO: "America/Denver",
  NV: "America/Los_Angeles", CA: "America/Los_Angeles",
};

// Real, official administrative aliases for cities where Google's address
// formatting uses a sub-division name instead of the city itself — not a
// distance guess, a fact (NYC's 5 boroughs are legally part of NYC).
// Extend this as other consolidated-metro cities are added to the pipeline.
const CITY_ALIASES: Record<string, string[]> = {
  "New York": ["New York", "Brooklyn", "Queens", "Bronx", "Staten Island", "Manhattan", "Long Island City", "Astoria"],
};

function resolveTimezone(stateAbbr: string): string {
  return STATE_TIMEZONE[stateAbbr.toUpperCase()] ?? "America/New_York";
}

function slugify(name: string, city: string): string {
  return `${name}-${city}`
    .toLowerCase()
    .normalize("NFD").replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

/**
 * Variantes de búsqueda, priorizando college-first (§2 del pedido): primero
 * lo directamente asociado al campus, después alrededor del campus, recién
 * al final nightlife general de la ciudad. `collegeQuery` es opcional —
 * ciudades sin universidad asociada solo corren las genéricas.
 */
function buildQueries(city: string, collegeQuery: string | null): string[] {
  const collegeFirst = collegeQuery
    ? [
        `college bars near ${collegeQuery}`,
        `bars near ${collegeQuery}`,
        `nightclubs near ${collegeQuery}`,
        `student nightlife near ${collegeQuery}`,
      ]
    : [];
  return [
    ...collegeFirst,
    `bars and nightclubs in ${city}`,
    `sports bars in ${city}`,
    `dance clubs in ${city}`,
    `lounges in ${city}`,
    `cocktail bars in ${city}`,
    `rooftop bars in ${city}`,
    `late night bars in ${city}`,
    `popular nightlife near downtown ${city}`,
  ];
}

/**
 * Reintenta solo fallos de red/timeout (p.ej. UND_ERR_BODY_TIMEOUT en
 * ciudades grandes con muchas llamadas seguidas) — nunca reintenta una
 * respuesta HTTP real de Google, esa se maneja donde ya se maneja (!res.ok).
 */
async function fetchWithRetry(url: string, init: RequestInit, retries = 3): Promise<Response> {
  for (let attempt = 0; ; attempt++) {
    try {
      return await fetch(url, init);
    } catch (err) {
      if (attempt >= retries) throw err;
      const delay = 500 * 2 ** attempt;
      console.error(`  fetch falló (${(err as Error).message}), reintentando en ${delay}ms...`);
      await new Promise((r) => setTimeout(r, delay));
    }
  }
}

/** Una sola query de Text Search — 20 resultados máx por llamada (límite de Google). */
async function searchOnce(query: string): Promise<PlaceSummary[]> {
  const res = await fetchWithRetry("https://places.googleapis.com/v1/places:searchText", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": PLACES_API_KEY!,
      "X-Goog-FieldMask": "places.id,places.displayName,places.formattedAddress,places.types",
    },
    body: JSON.stringify({ textQuery: query, maxResultCount: 20 }),
  });
  if (!res.ok) {
    console.error(`  searchText falló para "${query}" (${res.status}): ${await res.text()}`);
    return [];
  }
  const data = (await res.json()) as SearchResponse;
  return data.places ?? [];
}

/** Corre todas las variantes y fusiona resultados, deduplicando por place_id. */
async function searchCity(city: string, collegeQuery: string | null): Promise<PlaceSummary[]> {
  const queries = buildQueries(city, collegeQuery);
  const merged = new Map<string, PlaceSummary>();
  for (const q of queries) {
    console.log(`  buscando: "${q}"`);
    const results = await searchOnce(q);
    for (const p of results) if (!merged.has(p.id)) merged.set(p.id, p);
    await new Promise((r) => setTimeout(r, 200));
  }
  return [...merged.values()];
}

async function fetchDetails(placeId: string): Promise<PlaceDetails | null> {
  const fields = [
    "id", "displayName", "formattedAddress", "location", "nationalPhoneNumber",
    "websiteUri", "rating", "userRatingCount", "businessStatus", "types",
    "regularOpeningHours", "photos", "priceLevel", "addressComponents",
    "accessibilityOptions", "outdoorSeating", "goodForGroups",
    "goodForWatchingSports", "liveMusic", "reservable", "servesVegetarianFood", "restroom",
  ].join(",");
  const res = await fetchWithRetry(`https://places.googleapis.com/v1/places/${placeId}`, {
    headers: { "X-Goog-Api-Key": PLACES_API_KEY!, "X-Goog-FieldMask": fields },
  });
  if (!res.ok) {
    console.error(`  details falló (${res.status}): ${await res.text()}`);
    return null;
  }
  return (await res.json()) as PlaceDetails;
}

function firstPhotoUrl(details: PlaceDetails): string | null {
  const photoName = details.photos?.[0]?.name;
  if (!photoName) return null;
  return `https://places.googleapis.com/v1/${photoName}/media?maxWidthPx=1200&key=${PLACES_API_KEY}`;
}

/** Haversine — km entre dos puntos. Solo para mostrar distancia al campus en el reporte. */
function distanceKm(a: { lat: number; lng: number }, b: { lat: number; lng: number }): number {
  const R = 6371;
  const dLat = ((b.lat - a.lat) * Math.PI) / 180;
  const dLng = ((b.lng - a.lng) * Math.PI) / 180;
  const s = Math.sin(dLat / 2) ** 2 + Math.cos((a.lat * Math.PI) / 180) * Math.cos((b.lat * Math.PI) / 180) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(s));
}

/** Ubicación real del campus, vía Google — null si no se pudo resolver (nunca inventada). */
async function resolveCollegeLocation(collegeQuery: string): Promise<{ lat: number; lng: number } | null> {
  const results = await searchOnce(collegeQuery);
  const first = results[0];
  if (!first) return null;
  const details = await fetchDetails(first.id);
  if (!details?.location) return null;
  return { lat: details.location.latitude, lng: details.location.longitude };
}

async function main() {
  const city = cityArg!;
  const [cityName, stateAbbr] = city.split(",").map((s) => s.trim());
  const timezone = resolveTimezone(stateAbbr ?? "FL");

  const collegeLocation = collegeArg ? await resolveCollegeLocation(collegeArg) : null;
  if (collegeArg && !collegeLocation) {
    console.log(`  (no se pudo resolver la ubicación real de "${collegeArg}" — se omite el cálculo de distancia)`);
  }

  console.log(`Buscando venues reales en "${city}"${collegeArg ? ` (college-first: ${collegeArg})` : ""}...`);
  const results = await searchCity(city, collegeArg);
  console.log(`\n${results.length} candidatos únicos tras fusionar todas las queries.\n`);

  // Duplicados: contra TODA la tabla, por google_place_id (una cadena real
  // podría aparecer en más de una ciudad, pero un place_id nunca se repite).
  const { data: existing } = await supabase.from("venues").select("google_place_id").not("google_place_id", "is", null);
  const existingIds = new Set((existing ?? []).map((v) => v.google_place_id));

  // slug = name+city collides for real, distinct venues (chains with two
  // locations in one city, or two separate Google listings for the same
  // business at different addresses — both happened in the Las Vegas
  // batch). Track every slug already claimed, in the DB or earlier in this
  // same run, and disambiguate with the place_id rather than silently
  // dropping the insert on a unique-constraint error.
  const { data: existingSlugs } = await supabase.from("venues").select("slug");
  const claimedSlugs = new Set((existingSlugs ?? []).map((v) => v.slug));

  let validCandidates = 0, inserted = 0, insertFailed = 0, skippedDup = 0, skippedType = 0, skippedNoHours = 0, skippedClosed = 0, skippedWrongCity = 0, processed = 0;

  for (const summary of results) {
    if (processed >= limit) break;
    processed++;
    const name = summary.displayName?.text ?? "(sin nombre)";

    if (existingIds.has(summary.id)) {
      console.log(`  [dup]     ${name} — ya existe (google_place_id)`);
      skippedDup++;
      continue;
    }

    const details = await fetchDetails(summary.id);
    await new Promise((r) => setTimeout(r, 250));
    if (!details) continue;

    if (details.businessStatus && details.businessStatus !== "OPERATIONAL") {
      console.log(`  [cerrado] ${name} — businessStatus=${details.businessStatus}`);
      skippedClosed++;
      continue;
    }

    // Google's text search fuzzy-matches on street names ("University Dr"
    // exists in Davie, FL too) and occasionally returns results from a
    // totally different metro. A result whose own formatted address
    // doesn't contain the target city's name is a false positive, not a
    // "nearby suburb" judgment call — reject it outright rather than
    // writing the wrong city's venue under this city's label.
    //
    // Exception: consolidated multi-borough cities. Real, official NYC
    // venues in Brooklyn/Queens/the Bronx/Staten Island format their
    // Google address with the borough as the city, not "New York" — the
    // NYC batch rejected 11 genuine venues (House of Yes, Elsewhere,
    // Bossa Nova Civic Club...) before this was added. This is a factual
    // administrative alias, not a distance guess.
    const addressLower = details.formattedAddress?.toLowerCase() ?? "";
    const cityAliases = CITY_ALIASES[cityName] ?? [cityName];
    const inCity = cityAliases.some((alias) => addressLower.includes(alias.toLowerCase()));
    if (!inCity) {
      console.log(`  [ciudad]  ${name} — dirección real "${details.formattedAddress}" no está en ${cityName}`);
      skippedWrongCity++;
      continue;
    }

    const type = mapType(details.types);
    if (!type) {
      console.log(`  [tipo]    ${name} — types=${(details.types ?? []).join(",")} no mapea a nuestro enum`);
      skippedType++;
      continue;
    }

    // open_time/close_time son NOT NULL en el schema — si Google no tiene
    // horario real, no inventamos uno. Se salta, no se inserta a medias.
    const period = details.regularOpeningHours?.periods?.[0];
    if (!period?.open || !period?.close) {
      console.log(`  [horario] ${name} — Google no tiene horario real, se omite`);
      skippedNoHours++;
      continue;
    }

    const neighborhood =
      details.addressComponents?.find((c) => c.types?.includes("neighborhood"))?.longText ??
      details.addressComponents?.find((c) => c.types?.includes("sublocality"))?.longText ??
      cityName;

    let slug = slugify(name, cityName);
    if (claimedSlugs.has(slug)) {
      slug = `${slug}-${details.id.slice(-6).toLowerCase()}`;
    }
    claimedSlugs.add(slug);

    const row = {
      slug,
      name,
      type,
      neighborhood,
      address: details.formattedAddress ?? summary.formattedAddress ?? "",
      lat: details.location?.latitude ?? 0,
      lng: details.location?.longitude ?? 0,
      hook: "",
      description: "",
      rating: details.rating ?? 0,
      review_count: details.userRatingCount ?? 0,
      price_tier: details.priceLevel ? PRICE_LEVEL_MAP[details.priceLevel] ?? null : null,
      avg_spend: null,
      open_time: formatTime(period.open.hour, period.open.minute),
      close_time: formatTime(period.close.hour, period.close.minute),
      music_genres: [],
      vibes: [],
      dress_code: "",
      parking: "",
      crowd_level: "steady",
      best_arrival_time: "",
      peak_hours: "",
      popular_drinks: "[]",
      emoji: type === "club" ? "🎵" : type === "brewery" ? "🍺" : "🍸",
      image_url: firstPhotoUrl(details),
      instagram_handle: null,
      is_trending: false,
      phone: details.nationalPhoneNumber ?? null,
      website: details.websiteUri ?? null,
      google_place_id: details.id,
      business_status: details.businessStatus ?? null,
      google_synced_at: new Date().toISOString(),
      wheelchair_accessible: details.accessibilityOptions?.wheelchairAccessibleEntrance ?? null,
      outdoor_seating: details.outdoorSeating ?? null,
      good_for_groups: details.goodForGroups ?? null,
      good_for_watching_sports: details.goodForWatchingSports ?? null,
      has_live_music: details.liveMusic ?? null,
      reservable: details.reservable ?? null,
      serves_vegetarian_food: details.servesVegetarianFood ?? null,
      restroom: details.restroom ?? null,
      amenities_synced_at: new Date().toISOString(),
      city: cityName,
      country: "US",
      timezone,
    };

    const distLabel = collegeLocation && details.location
      ? ` — ${distanceKm(collegeLocation, { lat: details.location.latitude, lng: details.location.longitude }).toFixed(1)}km del campus`
      : "";
    console.log(`  [nuevo]   ${name} (${type}) — ${row.address}${distLabel}  [${details.id}]`);
    validCandidates++;

    if (!dryRun) {
      const { error } = await supabase.from("venues").insert(row);
      if (error) {
        console.error(`    ERROR insertando: ${error.message}`);
        insertFailed++;
      } else {
        inserted++;
      }
    }
  }

  console.log(`\n${dryRun ? "[DRY RUN] " : ""}Resumen para ${city}:`);
  console.log(`  candidatos válidos: ${validCandidates}`);
  if (!dryRun) {
    console.log(`  insertados de verdad: ${inserted}`);
    console.log(`  fallaron al insertar: ${insertFailed}`);
  }
  console.log(`  duplicados:         ${skippedDup}`);
  console.log(`  tipo no relevante:  ${skippedType}`);
  console.log(`  sin horario real:   ${skippedNoHours}`);
  console.log(`  cerrados:           ${skippedClosed}`);
  console.log(`  ciudad incorrecta:  ${skippedWrongCity}`);
}

main();
