/**
 * Enriquece stadiums con foto + descripción reales de Google Places (API
 * New — Text Search + Place Details). Regla dura: si Google no devuelve un
 * campo, se deja tal cual está (nunca se inventa un valor). Mismo patrón
 * que enrich-venues.ts, pero para la tabla `stadiums` (image_url,
 * description) — agregadas en supabase/stadium_image_description.sql.
 *
 * Uso: npm run enrich:stadiums [-- --dry-run]
 *
 * Requiere en .env.local: GOOGLE_PLACES_API_KEY, NEXT_PUBLIC_SUPABASE_URL,
 * SUPABASE_SERVICE_ROLE_KEY.
 */
import { createClient } from "@supabase/supabase-js";
// @ts-expect-error — mismo fallback de transporte que enrich-venues.ts
import ws from "ws";
import { photoUri, placesClient, unwrap } from "./lib/places-calls";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
  console.error("Faltan env vars: NEXT_PUBLIC_SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY");
  process.exit(1);
}

// Este script NO lo reemplaza la pasada única: trabaja sobre `stadiums`, otra
// tabla, con 22 filas. Sin PLACES_SPEND=1 no toca la red.
const places = placesClient("enrich-stadiums");

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  realtime: { transport: ws as unknown as typeof WebSocket },
});

const dryRun = process.argv.includes("--dry-run");

interface StadiumRow {
  id: string;
  name: string;
  address: string;
}

async function findPlaceId(name: string, address: string): Promise<string | null> {
  const data = await unwrap<{ places?: { id: string }[] }>(
    () => places.searchText(`${name}, ${address}`, ["places.id"]),
    `buscar ${name}`,
  );
  return data?.places?.[0]?.id ?? null;
}

async function fetchPlaceDetails(placeId: string) {
  // editorialSummary es nivel Atmosphere, el más caro del catálogo. Son 22
  // stadiums, así que se paga una vez y ya — pero vale saberlo antes de
  // ponerle un --all a esto.
  return unwrap<{ editorialSummary?: { text?: string }; photos?: { name: string }[] }>(
    () => places.placeDetails(placeId, ["id", "editorialSummary", "photos"]),
    `details ${placeId}`,
  );
}

async function main() {
  const { data: stadiums, error } = await supabase.from("stadiums").select("id,name,address");
  if (error || !stadiums) {
    console.error("No se pudieron leer los stadiums:", error?.message);
    process.exit(1);
  }

  console.log(`Enriqueciendo ${stadiums.length} stadiums${dryRun ? " (dry-run)" : ""}...`);

  for (const stadium of stadiums as StadiumRow[]) {
    console.log(`\n${stadium.name}`);
    const placeId = await findPlaceId(stadium.name, stadium.address);
    if (!placeId) {
      console.log("  no encontrado en Google — sin cambios");
      continue;
    }
    const details = await fetchPlaceDetails(placeId);
    if (!details) continue;

    const update: Record<string, unknown> = {};
    if (details.editorialSummary?.text) update.description = details.editorialSummary.text;
    // ÚNICO cambio de comportamiento de esta migración, y es a propósito:
    // antes se guardaba el URL con `&key=${GOOGLE_PLACES_API_KEY}` adentro, y
    // `stadiums` se lee con la anon key — o sea, la clave facturable quedaba
    // publicada. Es el mismo bug que `fix-venue-photos.ts` arregló en `venues`
    // el 2026-09-13; acá había quedado. Ahora se guarda el URL de CDN
    // resuelto, sin clave y dimensionado, que es la forma que ya usa el resto.
    const photoName = details.photos?.[0]?.name;
    if (photoName) {
      const uri = await photoUri(places, photoName);
      if (uri) update.image_url = uri;
    }

    if (Object.keys(update).length === 0) {
      console.log("  Google no devolvió foto ni descripción — sin cambios");
      continue;
    }
    console.log(`  campos actualizados: ${Object.keys(update).join(", ")}`);
    if (dryRun) continue;

    const { error: updateError } = await supabase.from("stadiums").update(update).eq("id", stadium.id);
    if (updateError) console.error(`  ERROR guardando: ${updateError.message}`);

    await new Promise((r) => setTimeout(r, 250));
  }

  console.log("\nListo.");
}

main();
