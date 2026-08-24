/**
 * Corrige price_tier con datos reales de Google Places (API New — Place
 * Details, campo priceLevel). Antes, price_tier era `not null default 2`,
 * así que la mayoría de venues (Miami 87%, Austin 66%) tenían un "2" que
 * Google nunca dio — era el default silencioso de la columna, no un dato
 * real. La migración `price_tier_allow_null.sql` ya quitó el NOT
 * NULL/default, así que ahora NULL es un valor legítimo ("desconocido").
 *
 * Regla dura: si Google devuelve un priceLevel real, se mapea a 1-4 con
 * PRICE_LEVEL_MAP. Si Google no tiene priceLevel para ese venue (campo
 * ausente en la respuesta), se escribe NULL — nunca se inventa un valor
 * ni se deja el "2" viejo, que no es más confiable que NULL.
 *
 * avg_spend NO se toca: Google no da una cifra de gasto confiable para
 * vida nocturna, así que se deja como está (0) en vez de inventar un
 * número.
 *
 * Resumable: usa un checkpoint local (scripts/.price-tier-progress.json)
 * con los ids de venues ya procesados en este run. Reiniciar el script
 * continúa donde quedó en vez de volver a pegarle a la API por venues ya
 * hechos. Cada escritura a Supabase es individual e inmediata (no hay
 * "todo o nada": si el proceso muere a mitad de camino, lo ya escrito
 * queda escrito).
 *
 * Uso: npm run fix-price-tiers [-- --dry-run] [-- --only=slug1,slug2]
 */
import { createClient } from "@supabase/supabase-js";
// @ts-expect-error — 'ws' no trae tipos propios, ver enrich-venues.ts
import ws from "ws";
import fs from "node:fs";
import path from "node:path";

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
const onlyArg = args.find((a) => a.startsWith("--only="));
const onlySlugs = onlyArg ? onlyArg.replace("--only=", "").split(",") : null;

const PROGRESS_FILE = path.join(__dirname, ".price-tier-progress.json");

const PRICE_LEVEL_MAP: Record<string, number> = {
  PRICE_LEVEL_FREE: 1,
  PRICE_LEVEL_INEXPENSIVE: 1,
  PRICE_LEVEL_MODERATE: 2,
  PRICE_LEVEL_EXPENSIVE: 3,
  PRICE_LEVEL_VERY_EXPENSIVE: 4,
};

interface VenueRow {
  id: string;
  slug: string;
  name: string;
  city: string;
  google_place_id: string;
  price_tier: number | null;
}

interface PlaceDetails {
  id: string;
  priceLevel?: string;
}

function loadProgress(): Set<string> {
  if (!fs.existsSync(PROGRESS_FILE)) return new Set();
  try {
    const raw = JSON.parse(fs.readFileSync(PROGRESS_FILE, "utf-8"));
    return new Set(raw.done as string[]);
  } catch {
    return new Set();
  }
}

function saveProgress(done: Set<string>) {
  fs.writeFileSync(PROGRESS_FILE, JSON.stringify({ done: Array.from(done) }, null, 0));
}

async function fetchPriceLevel(placeId: string): Promise<{ priceLevel?: string } | null> {
  const res = await fetch(`https://places.googleapis.com/v1/places/${placeId}`, {
    headers: { "X-Goog-Api-Key": PLACES_API_KEY!, "X-Goog-FieldMask": "id,priceLevel" },
  });
  if (!res.ok) {
    console.error(`  details falló (${res.status}): ${await res.text()}`);
    return null;
  }
  return (await res.json()) as PlaceDetails;
}

async function fixVenue(venue: VenueRow): Promise<"ok" | "error"> {
  const details = await fetchPriceLevel(venue.google_place_id);
  if (!details) return "error";

  const mapped = details.priceLevel ? PRICE_LEVEL_MAP[details.priceLevel] ?? null : null;
  const newValue = mapped ?? null;

  console.log(
    `${venue.name} (${venue.city}/${venue.slug}): price_tier ${venue.price_tier ?? "NULL"} -> ${newValue ?? "NULL"}` +
      (details.priceLevel ? ` [Google: ${details.priceLevel}]` : " [Google: sin priceLevel]")
  );

  if (dryRun) return "ok";

  const { error } = await supabase.from("venues").update({ price_tier: newValue }).eq("id", venue.id);
  if (error) {
    console.error(`  ERROR guardando: ${error.message}`);
    return "error";
  }
  return "ok";
}

// El cliente de supabase-js pagina a 1000 filas por default (mismo
// default que PostgREST) — sin esto, con 1817 venues, se procesarían
// solo los primeros 1000 y listo, en silencio, sin error.
async function fetchAllVenues(): Promise<VenueRow[]> {
  const all: VenueRow[] = [];
  const pageSize = 1000;
  let offset = 0;
  for (;;) {
    let query = supabase
      .from("venues")
      .select("id,slug,name,city,google_place_id,price_tier")
      .order("id")
      .range(offset, offset + pageSize - 1);
    if (onlySlugs) query = query.in("slug", onlySlugs);
    const { data, error } = await query;
    if (error) {
      console.error("No se pudieron leer los venues:", error.message);
      process.exit(1);
    }
    if (!data || data.length === 0) break;
    all.push(...(data as VenueRow[]));
    if (data.length < pageSize) break;
    offset += pageSize;
  }
  return all;
}

async function main() {
  const venues = await fetchAllVenues();

  const progress = loadProgress();
  const pending = (venues as VenueRow[]).filter((v) => !progress.has(v.id));

  console.log(
    `${venues.length} venues totales, ${progress.size} ya procesados en runs previos, ${pending.length} pendientes${dryRun ? " (dry-run)" : ""}.`
  );

  let ok = 0;
  let errors = 0;
  let real = 0;
  let nulled = 0;

  for (const venue of pending) {
    if (!venue.google_place_id) {
      console.log(`${venue.name}: sin google_place_id — se salta`);
      continue;
    }
    const result = await fixVenue(venue);
    if (result === "ok") {
      ok++;
      if (!dryRun) {
        progress.add(venue.id);
        saveProgress(progress);
      }
    } else {
      errors++;
    }
    // Respeta el rate limit de Google.
    await new Promise((r) => setTimeout(r, 250));
  }

  console.log(`\nListo. ok=${ok} errors=${errors} (progreso guardado en ${PROGRESS_FILE})`);
}

main();
