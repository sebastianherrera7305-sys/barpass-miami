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

interface StadiumRow {
  id: string;
  name: string;
  address: string;
}

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
  const data = (await res.json()) as { places?: { id: string }[] };
  return data.places?.[0]?.id ?? null;
}

async function fetchPlaceDetails(placeId: string) {
  const fields = ["id", "editorialSummary", "photos"].join(",");
  const res = await fetch(`https://places.googleapis.com/v1/places/${placeId}`, {
    headers: { "X-Goog-Api-Key": PLACES_API_KEY!, "X-Goog-FieldMask": fields },
  });
  if (!res.ok) {
    console.error(`  details falló (${res.status}): ${await res.text()}`);
    return null;
  }
  return (await res.json()) as { editorialSummary?: { text?: string }; photos?: { name: string }[] };
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
    const photoName = details.photos?.[0]?.name;
    if (photoName) {
      update.image_url = `https://places.googleapis.com/v1/${photoName}/media?maxWidthPx=1200&key=${PLACES_API_KEY}`;
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
