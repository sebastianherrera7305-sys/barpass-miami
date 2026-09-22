/**
 * LA PASADA ÚNICA: una sola llamada a Google por venue, en vez de cinco.
 *
 * QUÉ REEMPLAZA
 *   backfill-venue-hours.ts     regularOpeningHours.periods
 *   fix-venue-types.ts          primaryType, types, servesBeer/Wine/Cocktails
 *   fix-price-tiers.ts          priceLevel
 *   fix-venue-photos.ts         photos
 *   refresh-venue-core-data.ts  rating, reviews, web, teléfono, horarios, foto
 * y, de yapa, los amenities de enrich-venues.ts.
 *
 * POR QUÉ CUESTA MENOS
 * Places API (New) factura cada request UNA vez, al SKU más caro que toca su
 * field mask. Las cinco pasadas pagaban: Enterprise (horarios) + Atmosphere
 * (tipos) + Enterprise (precio) + IDs-Only (fotos) + Enterprise (core). Esta
 * pide todo junto y paga UN Atmosphere. Pedir MÁS campos en la misma llamada no
 * sale más caro; pedir los mismos campos en llamadas separadas sí. El barrido
 * del 14 de septiembre — 2.510 venues, USD 655 en la tarjeta del fundador —
 * salió de esa diferencia.
 *
 * CÓMO NO VUELVE A PASAR
 *  - No gasta nada por default. Sin --spend no sale un solo request: el
 *    PlacesClient corta antes del fetch, no dentro de él.
 *  - Imprime a quién va a tocar y cuánto estima gastar ANTES de empezar.
 *  - Tiene techo de presupuesto (--max-usd, default 10). Barrer el catálogo
 *    entero tiene que ser una decisión escrita a mano, no el default.
 *  - Los números son estimaciones de precios de lista SIN VERIFICAR. Ver el
 *    banner de lib/places-pricing.ts antes de citarlos.
 *
 * PROCEDENCIA (CLAUDE.md + skill venue-intelligence)
 * Si Google no devuelve un campo, la columna NO se toca. Un vacío es un hecho;
 * un valor adivinado es una mentira que dura meses. Toda la lógica está en
 * venue-google-patch.ts, sin red ni base, y tiene tests.
 *
 *   npx tsx scripts/refresh-venue-from-google.ts --city=Gainesville
 *   npx tsx scripts/refresh-venue-from-google.ts --city=Gainesville --spend --write
 */
import { createClient } from "@supabase/supabase-js";
// @ts-expect-error — 'ws' ships no types, same as the other scripts.
import ws from "ws";
import { photoUri, placesClient, unwrap } from "./lib/places-calls";
import { estimateSweep, formatUsd } from "./lib/places-pricing";
import { buildPatch } from "./venue-google-patch";
import {
  REFRESH_FIELD_MASK,
  type GooglePlace,
  type VenueRow,
} from "./venue-google-fields";


const SELECT_COLUMNS =
  "id,name,city,type,google_place_id,hours,rating,review_count,price_tier," +
  "image_url,website,phone,business_status,excluded_reason,field_sources," +
  "wheelchair_accessible,outdoor_seating,good_for_groups,good_for_watching_sports," +
  "has_live_music,reservable,serves_vegetarian_food,restroom";

const args = process.argv.slice(2);
const flag = (name: string) => args.includes(`--${name}`);
const value = (name: string) =>
  args.find((a) => a.startsWith(`--${name}=`))?.slice(name.length + 3);
const list = (name: string) =>
  value(name)?.split(",").map((s) => s.trim()).filter(Boolean) ?? null;
const num = (name: string, fallback: number) => {
  const raw = value(name);
  if (raw === undefined) return fallback;
  const n = Number(raw);
  return Number.isFinite(n) ? n : fallback;
};

const city = value("city");
const ids = list("ids");
const slugs = list("slugs");
const staleDays = value("stale-days") ? num("stale-days", 30) : null;
const all = flag("all");
const limit = value("limit") ? num("limit", Infinity) : Infinity;
const spend = flag("spend");
const write = flag("write");
const maxUsd = num("max-usd", 10);
const skipPhotos = flag("no-photos");
const includeExcluded = flag("include-excluded");

function usage(message: string): never {
  console.error(`\n${message}\n
Selector (obligatorio, elegí uno):
  --city=Gainesville          una ciudad
  --ids=uuid,uuid             venues puntuales
  --slugs=slug,slug           venues puntuales por slug
  --stale-days=30             los que no se sincronizan hace N días (o nunca)
  --all                       TODO el catálogo — decisión explícita, nunca default

Opciones:
  --limit=N                   cortar después de N venues
  --spend                     hacer las llamadas de verdad (sin esto: simulación, $0)
  --write                     escribir en Supabase (requiere --spend)
  --max-usd=10                techo de gasto estimado; arriba de esto se planta
  --no-photos                 no resolver fotos (evita el SKU extra de Place Photo)
  --include-excluded          incluir filas excluidas, para poder restaurarlas\n`);
  process.exit(1);
}

if (!city && !ids && !slugs && staleDays === null && !all) {
  usage("Falta un selector. Barrer los 4.417 venues no puede ser el default.");
}
if (write && !spend) usage("--write necesita --spend: sin llamadas no hay nada que escribir.");

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
  console.error("Faltan env vars: NEXT_PUBLIC_SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY");
  process.exit(1);
}
const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  realtime: { transport: ws as unknown as typeof WebSocket },
});

/** PostgREST corta en 1.000 filas: un select pelado ya reportó "listo, 3.919
 *  venues" habiendo tocado 999. Se pagina siempre. */
async function selectVenues(): Promise<VenueRow[]> {
  const rows: VenueRow[] = [];
  for (let from = 0; ; from += 1000) {
    let q = supabase
      .from("venues")
      .select(SELECT_COLUMNS)
      .not("google_place_id", "is", null)
      .order("id")
      .range(from, from + 999);

    if (city) q = q.eq("city", city);
    if (ids) q = q.in("id", ids);
    if (slugs) q = q.in("slug", slugs);
    if (!includeExcluded) {
      q = q.is("excluded_reason", null);
      // `not.eq` es NULL, no true, para los venues que Google nunca alcanzó:
      // la forma `or` los conserva en vez de descartarlos en silencio.
      q = q.or("business_status.is.null,business_status.neq.CLOSED_PERMANENTLY");
    }
    if (staleDays !== null) {
      const cutoff = new Date(Date.now() - staleDays * 86_400_000).toISOString();
      q = q.or(`google_synced_at.is.null,google_synced_at.lt.${cutoff}`);
    }

    const { data, error } = await q;
    if (error) throw new Error(error.message);
    rows.push(...((data ?? []) as unknown as VenueRow[]));
    if ((data?.length ?? 0) < 1000) break;
  }
  return rows;
}

function describeSelection(): string {
  if (ids) return `${ids.length} id(s)`;
  if (slugs) return `${slugs.length} slug(s)`;
  if (city) return `ciudad = ${city}`;
  if (staleDays !== null) return `sin sincronizar hace más de ${staleDays} días`;
  return "TODO el catálogo";
}

async function main() {
  const selected = await selectVenues();
  const targets = Number.isFinite(limit) ? selected.slice(0, limit) : selected;
  // Sólo se compra foto para la fila que no tiene ninguna: es un request aparte,
  // con su propio SKU, y una foto que ya está no vale volver a pagarla.
  const photoCandidates = skipPhotos ? 0 : targets.filter((v) => !v.image_url).length;

  const details = estimateSweep("details", REFRESH_FIELD_MASK, targets.length);
  const photos = estimateSweep("photo", [], photoCandidates);
  const totalUsd = details.usd + photos.usd;

  console.log(`\nrefresh-venue-from-google — ${describeSelection()}`);
  console.log(`  venues seleccionados : ${selected.length}${targets.length !== selected.length ? ` (se procesan ${targets.length} por --limit)` : ""}`);
  console.log(`  1 llamada por venue  : Place Details, SKU ${details.tier} -> ${formatUsd(details.usd)}`);
  console.log(`  fotos a resolver     : ${photoCandidates} -> ${formatUsd(photos.usd)}`);
  console.log(`  GASTO ESTIMADO       : ${formatUsd(totalUsd)}  (estimación de precios de lista, no una factura)`);
  console.log(`  escritura a Supabase : ${write ? "SÍ" : "no (--write para escribir)"}`);

  if (!spend) {
    console.log(
      `\n[SIMULACIÓN] No se hizo ninguna llamada a Google y no se gastó nada.\n` +
        `Para ejecutarlo de verdad: agregá --spend (y --write para guardar).\n`,
    );
    return;
  }
  if (totalUsd > maxUsd) {
    console.error(
      `\nPlantado: el estimado (${formatUsd(totalUsd)}) supera el techo de ${formatUsd(maxUsd)}.\n` +
        `Si es intencional, re-ejecutá con --max-usd=${Math.ceil(totalUsd)}.\n` +
        `Ese techo existe porque el 14-sep nadie vio el número antes de gastarlo.\n`,
    );
    process.exit(1);
  }

  // Un solo cliente por script: el medidor cachea por place_id dentro del run
  // y su informe final resume todo lo gastado por este proceso.
  const places = placesClient("refresh-venue-from-google", { spend: true });
  const at = new Date().toISOString();
  let touched = 0, unchanged = 0, failed = 0, photosResolved = 0;
  const absentTally: Record<string, number> = {};

  for (const v of targets) {
    // `unwrap` traduce los cuatro estados del medidor a "objeto o null" y se
    // encarga de los reintentos (red y 429/5xx, nunca un 4xx real). null acá
    // significa siempre lo mismo: no hay dato utilizable, no se escribe nada.
    // Si el tope de llamadas se alcanzó, las que siguen devuelven null sin
    // gastar — el informe final dice cuántas se rechazaron.
    const g = await unwrap<GooglePlace>(
      () => places.placeDetails<GooglePlace>(v.google_place_id!, REFRESH_FIELD_MASK),
      `details ${v.name}`,
    );
    if (!g) {
      failed++;
      continue;
    }

    const result = buildPatch(v, g, { at, placeId: v.google_place_id!, resolvePhotos: !skipPhotos });
    for (const field of result.absent) absentTally[field] = (absentTally[field] ?? 0) + 1;

    if (result.photoToResolve) {
      // photoUri() ya descarta cualquier URL que todavía traiga la key:
      // venues.image_url es legible con la anon key y una clave facturable ahí
      // es una fuga, no un detalle.
      const uri = await photoUri(places, result.photoToResolve);
      if (uri) {
        result.patch.image_url = uri;
        result.changed.push("image_url");
        photosResolved++;
      }
    }

    if (result.changed.length === 0) {
      unchanged++;
    } else {
      console.log(`  ${v.name} (${v.city ?? "?"}) → ${result.changed.join(", ")}`);
      touched++;
    }

    if (write) {
      const { error } = await supabase.from("venues").update(result.patch).eq("id", v.id);
      if (error) {
        console.error(`    ERROR ${v.name}: ${error.message}`);
        failed++;
      }
    }
  }

  console.log(
    `\n${write ? "" : "[SIN --write] "}` +
      `con cambios: ${touched}   sin novedad: ${unchanged}   ` +
      `fotos resueltas: ${photosResolved}   fallaron: ${failed}`,
  );
  // Lo que Google no contestó se cuenta, no se rellena. Un conteo alto acá es
  // un dato sobre Google, no una columna que haya que completar a mano.
  for (const [field, count] of Object.entries(absentTally).sort((a, b) => b[1] - a[1])) {
    console.log(`  sin dato en Google: ${field.padEnd(12)} ${count}`);
  }
  places.printReport();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
