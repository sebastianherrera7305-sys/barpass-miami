/**
 * Measures how many venues are in the catalogue twice, and what hangs off each
 * copy. READ-ONLY by default — `--dry-run` is the default and `--apply` is not
 * implemented on purpose: deciding which of two rows survives is a decision
 * with attached events, check-ins and passes behind it, and it should be made
 * by a person reading this report.
 *
 *   npm run find:duplicates                  # full catalogue
 *   npm run find:duplicates -- --city=Gainesville
 *   npm run find:duplicates -- --top=15      # deepest 15 groups with dependents
 *   npm run find:duplicates -- --json=out.json
 *
 * The grouping logic lives in scripts/duplicate-venue-rules.ts and is tested in
 * duplicate-venue-rules.test.ts — evidence only (same google_place_id, or same
 * normalized address within a few metres), never a similar name.
 *
 * Every read here pages. PostgREST caps one response at 1000 rows no matter
 * how many match, and it does not promise an order, so an unpaginated count is
 * not a small count — it is a wrong one. That exact bug is what created the
 * MacDinton's duplicate: add-venues.ts checked for an existing google_place_id
 * with a single unpaginated select, saw an arbitrary 1000 of the ~3900 rows,
 * and re-inserted a venue it already had.
 */
import { writeFileSync } from "node:fs";
import { createClient } from "@supabase/supabase-js";
// @ts-expect-error — 'ws' ships no types, same as the other scripts.
import ws from "ws";
import {
  groupDuplicates,
  isResolved,
  type DuplicateGroup,
  type VenueRow,
} from "./duplicate-venue-rules";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
  console.error("Faltan env vars: NEXT_PUBLIC_SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY");
  process.exit(1);
}
const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  realtime: { transport: ws as unknown as typeof WebSocket },
});

const args = process.argv.slice(2);
const apply = args.includes("--apply");
const cityArg = args.find((a) => a.startsWith("--city="))?.slice("--city=".length) ?? null;
const jsonArg = args.find((a) => a.startsWith("--json="))?.slice("--json=".length) ?? null;
const top = Number(args.find((a) => a.startsWith("--top="))?.slice("--top=".length) ?? 15);

if (apply) {
  console.error(
    "--apply no existe en este script a propósito: es de medición. " +
      "Una fila borrada con un evento publicado colgando es peor que el duplicado.",
  );
  process.exit(1);
}

const COLUMNS =
  "id,name,slug,city,address,lat,lng,review_count,rating,google_place_id," +
  "excluded_reason,business_status,image_url,created_at,google_synced_at";

/** Every child table that points at venues.id, with the column that does it.
 *  A survivor decision that ignores these orphans real user data — host_events
 *  is even `on delete restrict`, so a delete would simply fail. */
const DEPENDENTS: { table: string; column: string; idIsText?: boolean }[] = [
  { table: "events", column: "venue_id" },
  { table: "host_events", column: "venue_id" },
  { table: "venue_media", column: "venue_id" },
  { table: "venue_checkins", column: "venue_id" },
  { table: "venue_menu_items", column: "venue_id" },
  { table: "venue_experience_tags", column: "venue_id" },
  { table: "venue_age_brackets", column: "venue_id" },
  { table: "venue_age_reports", column: "venue_id" },
  { table: "venue_price_reports", column: "venue_id" },
  { table: "venue_posts", column: "venue_id" },
  { table: "venue_owners", column: "venue_id" },
  { table: "venue_tabs", column: "venue_id" },
  { table: "promos", column: "venue_id" },
  { table: "favorites", column: "venue_id" },
  { table: "passes", column: "venue_id", idIsText: true },
];

async function selectAllVenues(): Promise<VenueRow[]> {
  const out: VenueRow[] = [];
  const page = 1000;
  for (let from = 0; ; from += page) {
    let q = supabase.from("venues").select(COLUMNS).range(from, from + page - 1);
    if (cityArg) q = q.eq("city", cityArg);
    const { data, error } = await q;
    if (error) throw new Error(`venues page ${from}: ${error.message}`);
    const rows = (data ?? []) as unknown as VenueRow[];
    out.push(...rows);
    if (rows.length < page) return out;
  }
}

/** Counts, per venue id, what each child table holds. Only called for ids that
 *  are actually in a duplicate group — 15 head counts × a few hundred ids. */
async function countDependents(ids: string[]): Promise<Map<string, Record<string, number>>> {
  const byId = new Map<string, Record<string, number>>(ids.map((id) => [id, {}]));
  for (const dep of DEPENDENTS) {
    for (let i = 0; i < ids.length; i += 100) {
      const chunk = ids.slice(i, i + 100);
      const { data, error } = await supabase
        .from(dep.table)
        .select(dep.column)
        .in(dep.column, chunk);
      if (error) {
        // A table that does not exist in this project yet is not a failure of
        // the measurement; say so once and move on.
        if (/does not exist|schema cache/i.test(error.message)) {
          console.warn(`  (skip ${dep.table}: ${error.message})`);
          break;
        }
        throw new Error(`${dep.table}: ${error.message}`);
      }
      for (const r of (data ?? []) as unknown as Record<string, string>[]) {
        const id = r[dep.column];
        const bucket = byId.get(id);
        if (!bucket) continue;
        bucket[dep.table] = (bucket[dep.table] ?? 0) + 1;
      }
    }
  }
  return byId;
}

const depsLabel = (d: Record<string, number> | undefined) => {
  const entries = Object.entries(d ?? {}).filter(([, n]) => n > 0);
  return entries.length ? entries.map(([t, n]) => `${t}=${n}`).join(" ") : "nada";
};

const servable = (r: VenueRow) =>
  !r.excluded_reason && r.business_status !== "CLOSED_PERMANENTLY";

function printGroup(
  g: DuplicateGroup,
  deps: Map<string, Record<string, number>>,
  index: number,
) {
  const [keep, ...drop] = g.rows;
  const spread = g.spreadMeters === null ? "sin coords" : `${g.spreadMeters.toFixed(0)}m`;
  console.log(
    `\n${index}. ${keep.name} — ${keep.city ?? "?"}  [${g.criterion}, ${spread}, ${g.rows.length} filas]`,
  );
  console.log(`   ${keep.address ?? "(sin dirección)"}`);
  // same-roof is a "read this" bucket, not a proposal: a hotel's lobby bar and
  // its rooftop share a door and are two real venues. Printing KEEP/drop there
  // would be inviting exactly the delete this script refuses to make.
  const proposes = g.criterion !== "same-roof";
  for (const r of g.rows) {
    const mark = !proposes ? "     " : r === keep ? "KEEP " : "drop ";
    const state = r.excluded_reason
      ? `excluida(${r.excluded_reason})`
      : r.business_status === "CLOSED_PERMANENTLY"
        ? "cerrada"
        : "servida";
    console.log(
      `   ${mark}${r.id}  ${r.review_count ?? 0} reviews  ${state}  ` +
        `creada ${(r.created_at ?? "").slice(0, 10)}  slug=${r.slug}`,
    );
    console.log(`         cuelga: ${depsLabel(deps.get(r.id))}`);
  }
  const stranded = proposes
    ? drop.filter((r) => Object.values(deps.get(r.id) ?? {}).some((n) => n > 0))
    : [];
  if (stranded.length) {
    console.log(`   ⚠︎  migrar antes de excluir: ${stranded.map((r) => r.id).join(", ")}`);
  }
}

async function main() {
  console.log(`[DRY RUN] find-duplicate-venues${cityArg ? ` — city=${cityArg}` : ""}\n`);
  const rows = await selectAllVenues();
  const served = rows.filter(servable);
  console.log(`filas en venues: ${rows.length}  (servibles: ${served.length})`);

  const groups = groupDuplicates(rows);
  const byCriterion = (c: DuplicateGroup["criterion"]) => groups.filter((g) => g.criterion === c);

  const real = groups.filter((g) => g.criterion !== "same-roof");
  const open = real.filter((g) => !isResolved(g));
  const resolved = real.filter((g) => isResolved(g));
  const sameRoof = byCriterion("same-roof");

  const rowsToExclude = open.reduce(
    (n, g) => n + g.rows.filter(servable).length - 1,
    0,
  );

  console.log("\n=== RESUMEN ===");
  console.log(`grupos duplicados por place_id      : ${byCriterion("place_id").length}`);
  console.log(`grupos duplicados por dirección+geo : ${byCriterion("address+geo").length}`);
  console.log(`  de esos, YA resueltos (una sola fila servible): ${resolved.length}`);
  console.log(`  ABIERTOS (dos o más filas visibles en producción): ${open.length}`);
  console.log(`filas que se irían si se cierran los abiertos: ${rowsToExclude}`);
  console.log(
    `\nmismo techo, nombres distintos (NO se tocan, sólo para leer): ${sameRoof.length} grupos`,
  );

  const ids = [...real, ...sameRoof].flatMap((g) => g.rows.map((r) => r.id));
  console.log(`\ncontando dependientes de ${ids.length} filas...`);
  const deps = await countDependents(ids);

  const weight = (g: DuplicateGroup) =>
    g.rows.reduce((n, r) => n + Object.values(deps.get(r.id) ?? {}).reduce((a, b) => a + b, 0), 0);

  console.log(`\n=== ${Math.min(top, open.length)} CASOS ABIERTOS MÁS FLAGRANTES ===`);
  const ranked = [...open].sort(
    (a, b) =>
      weight(b) - weight(a) ||
      b.rows.length - a.rows.length ||
      (b.rows[0].review_count ?? 0) - (a.rows[0].review_count ?? 0),
  );
  ranked.slice(0, top).forEach((g, i) => printGroup(g, deps, i + 1));

  if (resolved.length) {
    console.log(`\n=== YA RESUELTOS (${resolved.length}) — la copia vieja está excluida ===`);
    resolved.slice(0, top).forEach((g, i) => printGroup(g, deps, i + 1));
  }

  if (sameRoof.length) {
    console.log(`\n=== MISMO TECHO, NOMBRE DISTINTO (${sameRoof.length}) — revisar a mano ===`);
    sameRoof.slice(0, top).forEach((g, i) => printGroup(g, deps, i + 1));
  }

  if (jsonArg) {
    writeFileSync(
      jsonArg,
      JSON.stringify(
        { total: rows.length, served: served.length, groups: [...real, ...sameRoof] },
        null,
        2,
      ),
    );
    console.log(`\njson escrito en ${jsonArg}`);
  }

  console.log("\n[DRY RUN] no se escribió nada. Este script no escribe nunca.");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
