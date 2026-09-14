/**
 * Backfills `venues.hours` with the REAL weekly schedule from Google Places.
 *
 * Until now a venue carried one `open_time` / `close_time` pair with no concept
 * of days, and the importer kept only `regularOpeningHours.periods[0]` and threw
 * the rest away. So Rush Nightclub in Gainesville — open Friday 8pm-2am and
 * Saturday 9pm-2am, closed Sunday through Thursday — was stored as "20:00 to
 * 02:00" and the app confidently showed it as open on a Tuesday. For a venue
 * whose first period is Monday, Monday's hours were shown as Saturday's.
 *
 * Shape: [{"day":5,"open":"20:00","close":"02:00"}] where `day` is the day it
 * OPENS, 0 = Sunday (Google's numbering). A close earlier than the open means
 * it closes the next day; that is the normal case for nightlife and needs no
 * extra field.
 *
 * open_time / close_time are left alone as the legacy fallback for rows Google
 * has no hours for. A venue Google reports as having no regular hours gets
 * `hours = null`, never an invented schedule.
 *
 *   npm run backfill:hours -- [--city="Gainesville"] [--dry-run] [--limit=50]
 */
import { createClient } from "@supabase/supabase-js";
// @ts-expect-error — 'ws' ships no types, same as the other scripts.
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
const city = args.find((a) => a.startsWith("--city="))?.replace("--city=", "");
const limitArg = args.find((a) => a.startsWith("--limit="))?.replace("--limit=", "");
const limit = limitArg ? parseInt(limitArg, 10) : Infinity;

interface Period { open?: { day: number; hour: number; minute: number }; close?: { day: number; hour: number; minute: number } }
export interface DayHours { day: number; open: string; close: string }

const hhmm = (h: number, m: number) => `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}`;

/** Google periods -> our shape. A period with no close is a 24h venue, which
 *  Google encodes as a single open with no close; we render that as 00:00-23:59
 *  rather than dropping it, because "open all day" is real information. */
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

async function fetchPeriods(placeId: string): Promise<Period[] | undefined> {
  const res = await fetch(`https://places.googleapis.com/v1/places/${placeId}`, {
    headers: { "X-Goog-Api-Key": PLACES_API_KEY!, "X-Goog-FieldMask": "regularOpeningHours.periods" },
  });
  if (!res.ok) return undefined;
  const d = (await res.json()) as { regularOpeningHours?: { periods?: Period[] } };
  return d.regularOpeningHours?.periods;
}

async function main() {
  const rows: { id: string; name: string; city: string | null; google_place_id: string }[] = [];
  for (let from = 0; ; from += 1000) {
    let q = supabase.from("venues").select("id,name,city,google_place_id")
      .not("google_place_id", "is", null).is("excluded_reason", null).range(from, from + 999);
    if (city) q = q.eq("city", city);
    const { data, error } = await q;
    if (error) throw new Error(error.message);
    rows.push(...((data ?? []) as typeof rows));
    if ((data?.length ?? 0) < 1000) break;
  }
  console.log(`${rows.length} venues to backfill${city ? ` in ${city}` : ""}\n`);

  let written = 0, noHours = 0, failed = 0, processed = 0;
  for (const v of rows) {
    if (processed >= limit) break;
    processed++;
    const periods = await fetchPeriods(v.google_place_id);
    const hours = toWeeklyHours(periods);
    if (!hours) {
      noHours++;
    } else if (!dryRun) {
      const { error } = await supabase.from("venues").update({ hours }).eq("id", v.id);
      if (error) { console.error(`  ERROR ${v.name}: ${error.message}`); failed++; continue; }
      written++;
    } else { written++; }
    if (processed % 200 === 0) console.log(`  …${processed}/${rows.length}  escritos=${written} sin horario=${noHours}`);
    await new Promise((r) => setTimeout(r, 60));
  }
  console.log(`\n${dryRun ? "[DRY RUN] " : ""}con horario real: ${written}   sin horario en Google: ${noHours}   fallaron: ${failed}`);
}

main();
