/**
 * Enriquece los venues de Supabase con datos reales de Google Places
 * (API New — Text Search + Place Details). Regla dura: si Google no
 * devuelve un campo, se deja tal cual está (nunca se inventa un valor).
 *
 * Uso: npm run enrich [-- --dry-run] [-- --only=slug1,slug2]
 *
 * Requiere en .env.local: GOOGLE_PLACES_API_KEY, NEXT_PUBLIC_SUPABASE_URL,
 * SUPABASE_SERVICE_ROLE_KEY.
 */
import { createClient } from "@supabase/supabase-js";
// @ts-expect-error — 'ws' no trae tipos propios y no vale la pena instalar
// @types/ws solo para este transporte de fallback en Node 20.
import ws from "ws";

const PLACES_API_KEY = process.env.GOOGLE_PLACES_API_KEY;
const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!PLACES_API_KEY || !SUPABASE_URL || !SERVICE_ROLE_KEY) {
  console.error("Faltan env vars: GOOGLE_PLACES_API_KEY, NEXT_PUBLIC_SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY");
  process.exit(1);
}

// Node 20 no trae WebSocket nativo — el cliente de Supabase lo necesita
// para inicializar el canal de realtime aunque este script no lo use.
const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  realtime: { transport: ws as unknown as typeof WebSocket },
});

const args = process.argv.slice(2);
const dryRun = args.includes("--dry-run");
const onlyArg = args.find((a) => a.startsWith("--only="));
const onlySlugs = onlyArg ? onlyArg.replace("--only=", "").split(",") : null;

interface VenueRow {
  id: string;
  slug: string;
  name: string;
  address: string;
  phone: string | null;
  website: string | null;
  google_place_id: string | null;
  rating: number;
  review_count: number;
}

interface PlaceSearchResult {
  places?: { id: string }[];
}

interface PlaceDetails {
  id: string;
  nationalPhoneNumber?: string;
  websiteUri?: string;
  rating?: number;
  userRatingCount?: number;
  businessStatus?: string;
  location?: { latitude: number; longitude: number };
  regularOpeningHours?: { weekdayDescriptions?: string[] };
  photos?: { name: string }[];
  // Amenity/accessibility fields — Google omits the key entirely when it
  // doesn't know, rather than sending `false`, so `typeof x === "boolean"`
  // is the correct "did Google actually tell us" check below.
  accessibilityOptions?: { wheelchairAccessibleEntrance?: boolean };
  outdoorSeating?: boolean;
  goodForGroups?: boolean;
  goodForWatchingSports?: boolean;
  liveMusic?: boolean;
  reservable?: boolean;
  servesVegetarianFood?: boolean;
  restroom?: boolean;
}

/** Encuentra el place_id real en Google buscando por nombre + dirección. */
async function findPlaceId(name: string, address: string): Promise<string | null> {
  const res = await fetch("https://places.googleapis.com/v1/places:searchText", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": PLACES_API_KEY!,
      "X-Goog-FieldMask": "places.id",
    },
    body: JSON.stringify({ textQuery: `${name}, ${address}`, maxResultCount: 1 }),
  });
  if (!res.ok) {
    console.error(`  searchText falló (${res.status}): ${await res.text()}`);
    return null;
  }
  const data = (await res.json()) as PlaceSearchResult;
  return data.places?.[0]?.id ?? null;
}

/** Trae los detalles reales — solo los campos que existen en la respuesta. */
async function fetchPlaceDetails(placeId: string): Promise<PlaceDetails | null> {
  const fields = [
    "id", "nationalPhoneNumber", "websiteUri", "rating", "userRatingCount",
    "businessStatus", "location", "regularOpeningHours", "photos",
    "accessibilityOptions", "outdoorSeating", "goodForGroups",
    "goodForWatchingSports", "liveMusic", "reservable",
    "servesVegetarianFood", "restroom",
  ].join(",");
  const res = await fetch(`https://places.googleapis.com/v1/places/${placeId}`, {
    headers: { "X-Goog-Api-Key": PLACES_API_KEY!, "X-Goog-FieldMask": fields },
  });
  if (!res.ok) {
    console.error(`  details falló (${res.status}): ${await res.text()}`);
    return null;
  }
  return (await res.json()) as PlaceDetails;
}

/** URL directa de la primera foto real del venue — null si Google no tiene ninguna. */
function firstPhotoUrl(details: PlaceDetails): string | null {
  const photoName = details.photos?.[0]?.name;
  if (!photoName) return null;
  return `https://places.googleapis.com/v1/${photoName}/media?maxWidthPx=1200&key=${PLACES_API_KEY}`;
}

async function enrichVenue(venue: VenueRow): Promise<void> {
  console.log(`\n${venue.name} (${venue.slug})`);

  let placeId = venue.google_place_id;
  if (!placeId) {
    placeId = await findPlaceId(venue.name, venue.address);
    if (!placeId) {
      console.log("  no encontrado en Google — sin cambios");
      return;
    }
  }

  const details = await fetchPlaceDetails(placeId);
  if (!details) return;

  // Solo se escriben campos que Google realmente devolvió. Nunca se
  // sobreescribe con vacío algo que ya teníamos si Google no lo trae.
  const update: Record<string, unknown> = {
    google_place_id: placeId,
    google_synced_at: new Date().toISOString(),
  };
  if (details.nationalPhoneNumber) update.phone = details.nationalPhoneNumber;
  if (details.websiteUri) update.website = details.websiteUri;
  if (typeof details.rating === "number") update.rating = details.rating;
  if (typeof details.userRatingCount === "number") update.review_count = details.userRatingCount;
  if (details.businessStatus) update.business_status = details.businessStatus;
  const photoUrl = firstPhotoUrl(details);
  if (photoUrl) update.image_url = photoUrl;

  // Amenities: only written when Google's response actually included the
  // key. NULL stays NULL ("unknown") rather than ever being set to false.
  if (typeof details.accessibilityOptions?.wheelchairAccessibleEntrance === "boolean") {
    update.wheelchair_accessible = details.accessibilityOptions.wheelchairAccessibleEntrance;
  }
  if (typeof details.outdoorSeating === "boolean") update.outdoor_seating = details.outdoorSeating;
  if (typeof details.goodForGroups === "boolean") update.good_for_groups = details.goodForGroups;
  if (typeof details.goodForWatchingSports === "boolean") update.good_for_watching_sports = details.goodForWatchingSports;
  if (typeof details.liveMusic === "boolean") update.has_live_music = details.liveMusic;
  if (typeof details.reservable === "boolean") update.reservable = details.reservable;
  if (typeof details.servesVegetarianFood === "boolean") update.serves_vegetarian_food = details.servesVegetarianFood;
  if (typeof details.restroom === "boolean") update.restroom = details.restroom;
  update.amenities_synced_at = new Date().toISOString();

  console.log(`  campos actualizados: ${Object.keys(update).filter((k) => k !== "google_synced_at").join(", ")}`);

  if (dryRun) {
    console.log("  (--dry-run: no se escribió nada)");
    return;
  }

  const { error } = await supabase.from("venues").update(update).eq("id", venue.id);
  if (error) console.error(`  ERROR guardando: ${error.message}`);
}

async function main() {
  let query = supabase
    .from("venues")
    .select("id,slug,name,address,phone,website,google_place_id,rating,review_count");
  if (onlySlugs) query = query.in("slug", onlySlugs);

  const { data: venues, error } = await query;
  if (error || !venues) {
    console.error("No se pudieron leer los venues:", error?.message);
    process.exit(1);
  }

  console.log(`Enriqueciendo ${venues.length} venues${dryRun ? " (dry-run)" : ""}...`);

  for (const venue of venues as VenueRow[]) {
    await enrichVenue(venue);
    // Respeta el rate limit de Google — no dispares 176 requests de una.
    await new Promise((r) => setTimeout(r, 250));
  }

  console.log("\nListo.");
}

main();
