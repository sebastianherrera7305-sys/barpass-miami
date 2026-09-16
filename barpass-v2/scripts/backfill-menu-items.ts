/**
 * Pasa a `venue_menu_items` las cartas completas que ya extrajimos.
 *
 * El extractor guarda TODA la carta en la procedencia (`field_sources
 * .popular_drinks.items`) pero sólo los 6 principales llegaban a
 * `venues.popular_drinks`, que es lo único que la app podía leer: Boxcar
 * tiene 45 tragos extraídos y la app mostraba 6. Esto los mueve a la tabla
 * sin volver a tocar un solo sitio web.
 *
 * Idempotente: `upsert` sobre (venue_id, name), así que se puede correr las
 * veces que haga falta y después de cada barrido.
 *
 *   npm run backfill:menus -- --dry-run
 *   npm run backfill:menus -- --apply
 */
import { createClient } from "@supabase/supabase-js";
// @ts-expect-error — ws no trae tipos, mismo shim que el resto de los scripts.
import ws from "ws";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!SUPABASE_URL || !SERVICE_KEY) {
  console.error("Faltan NEXT_PUBLIC_SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY");
  process.exit(1);
}
const APPLY = process.argv.includes("--apply");
const supabase = createClient(SUPABASE_URL, SERVICE_KEY, { realtime: { transport: ws as unknown as typeof WebSocket } });

type Item = { name?: unknown; price?: unknown; category?: unknown };
type Prov = { items?: Item[]; source?: string; url?: string; method?: string; fetched_at?: string; at?: string };
type Row = { id: string; name: string; city: string | null; field_sources: Record<string, Prov> | null };

const DRINK_CATEGORIES = new Set(["cocktail", "beer", "wine", "shot", "spirit", "other"]);

async function main() {
  // PostgREST corta en 1000 filas: paginar o el backfill miente sin avisar.
  const venues: Row[] = [];
  for (let from = 0; ; from += 1000) {
    const { data, error } = await supabase
      .from("venues")
      .select("id,name,city,field_sources")
      .not("field_sources", "is", null)
      .range(from, from + 999);
    if (error) throw new Error(error.message);
    venues.push(...((data ?? []) as Row[]));
    if ((data?.length ?? 0) < 1000) break;
  }

  let venuesWithMenu = 0, rows = 0, skipped = 0;
  const payload: Array<Record<string, unknown>> = [];

  for (const v of venues) {
    const prov = v.field_sources?.popular_drinks;
    const items = prov?.items ?? [];
    if (!items.length) continue;
    venuesWithMenu++;
    const seen = new Set<string>();
    for (const it of items) {
      const name = typeof it.name === "string" ? it.name.trim().replace(/\s+/g, " ").slice(0, 120) : "";
      const price = Number(it.price);
      // Mismas puertas que el extractor: sin nombre o sin precio real, no entra.
      if (name.length < 2 || !Number.isFinite(price) || price < 0 || price > 2000) { skipped++; continue; }
      const key = name.toLowerCase();
      if (seen.has(key)) { skipped++; continue; }
      seen.add(key);
      const cat = String(it.category ?? "other").toLowerCase();
      payload.push({
        venue_id: v.id,
        name,
        price: Math.round(price * 100) / 100,
        category: DRINK_CATEGORIES.has(cat) ? cat : "other",
        is_drink: true,
        source: prov?.source ?? (prov?.method === "vision_extract" ? "venue menu image" : "venue website menu"),
        source_url: prov?.url ?? null,
        extracted_at: prov?.fetched_at ?? (prov?.at ? `${prov.at}T00:00:00Z` : new Date().toISOString()),
      });
      rows++;
    }
  }

  console.log(`${venuesWithMenu} venues con carta extraída → ${rows} ítems${skipped ? ` (${skipped} descartados por nombre/precio inválido o repetido)` : ""}`);
  const top = new Map<string, number>();
  for (const p of payload) top.set(p.venue_id as string, (top.get(p.venue_id as string) ?? 0) + 1);
  const byCount = [...top.entries()].sort((a, b) => b[1] - a[1]).slice(0, 5);
  for (const [id, n] of byCount) console.log(`   ${venues.find((v) => v.id === id)?.name ?? id}: ${n} ítems`);

  if (!APPLY) { console.log("\n[dry run] nada escrito — corré con --apply"); return; }

  // De a 500 para no pasarse del límite de payload de PostgREST.
  let written = 0;
  for (let i = 0; i < payload.length; i += 500) {
    const chunk = payload.slice(i, i + 500);
    const { error } = await supabase.from("venue_menu_items").upsert(chunk, { onConflict: "venue_id,name" });
    if (error) { console.error(`  lote ${i / 500 + 1} falló: ${error.message}`); continue; }
    written += chunk.length;
  }
  console.log(`\nEscritos ${written}/${payload.length} ítems.`);
}

main();
