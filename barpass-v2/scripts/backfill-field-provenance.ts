/**
 * Records where today's verified venue data came from.
 *
 * Run once after supabase/venue_field_provenance.sql. Everything written on
 * 2026-09-01 has a known origin, and that is exactly the data most worth
 * protecting from the next automated pass:
 *
 *   music_genres  → manual_research, one venue at a time against primary
 *                   sources. Replaced a fabricated ['hip_hop','house'] that
 *                   had been identical on 175 rows for two months.
 *   image_url     → google_places, stored in the pre-sized key-free form.
 *                   `enrich-venues.ts` still writes this column in the old
 *                   1.3MB form, so this entry is what tells a future run to
 *                   leave it alone.
 *   open_time /
 *   price_tier    → google_places, from the same backfill.
 *
 * Only fields that actually hold a value get an entry: claiming provenance
 * for an empty column would be its own small lie.
 *
 * Usage:
 *   npx tsx scripts/backfill-field-provenance.ts --dry-run
 *   npx tsx scripts/backfill-field-provenance.ts
 */

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!SUPABASE_URL || !SERVICE_KEY) throw new Error("Missing Supabase env vars");

const DRY_RUN = process.argv.includes("--dry-run");
const WRITTEN_ON = "2026-09-01";

const HEADERS = {
  apikey: SERVICE_KEY,
  Authorization: `Bearer ${SERVICE_KEY}`,
  "Content-Type": "application/json",
};

interface Row {
  id: string;
  name: string;
  music_genres: string[] | null;
  image_url: string | null;
  open_time: string | null;
  price_tier: number | null;
  google_synced_at: string | null;
  field_sources: Record<string, unknown> | null;
}

/** Pre-sized key-free photo URLs resolve to googleusercontent; the old
 *  1.3MB form is a places.googleapis.com redirect. Only the former was
 *  written by the 2026-09-01 backfill. */
function isSizedPhoto(url: string | null): boolean {
  return !!url && url.includes("googleusercontent.com");
}

function syncedToday(value: string | null): boolean {
  return !!value && value.startsWith(WRITTEN_ON);
}

async function main() {
  const rows: Row[] = [];
  for (const offset of [0, 1000]) {
    const res = await fetch(
      `${SUPABASE_URL}/rest/v1/venues` +
        `?select=id,name,music_genres,image_url,open_time,price_tier,google_synced_at,field_sources&order=name`,
      { headers: { ...HEADERS, "Range-Unit": "items", Range: `${offset}-${offset + 999}` } },
    );
    if (!res.ok) throw new Error(`select ${res.status}: ${await res.text()}`);
    rows.push(...((await res.json()) as Row[]));
  }
  console.log(`${rows.length} venues${DRY_RUN ? " (dry run)" : ""}\n`);

  let touched = 0;
  const tally: Record<string, number> = {};

  for (const r of rows) {
    const sources: Record<string, unknown> = { ...(r.field_sources ?? {}) };
    let changed = false;

    const note = (field: string, entry: Record<string, string>) => {
      if (sources[field]) return; // never overwrite an existing claim
      sources[field] = entry;
      tally[field] = (tally[field] ?? 0) + 1;
      changed = true;
    };

    if (r.music_genres?.length) {
      note("music_genres", { source: "manual_research", at: WRITTEN_ON, confidence: "high" });
    }
    if (isSizedPhoto(r.image_url)) {
      note("image_url", { source: "google_places", at: WRITTEN_ON });
    }
    // Hours and price only count as traced when the same backfill touched the
    // row — otherwise they predate this work and their origin is genuinely
    // unknown.
    if (syncedToday(r.google_synced_at)) {
      if (r.open_time) note("open_time", { source: "google_places", at: WRITTEN_ON });
      if (r.price_tier != null) note("price_tier", { source: "google_places", at: WRITTEN_ON });
    }

    if (!changed) continue;
    touched++;

    if (!DRY_RUN) {
      const res = await fetch(`${SUPABASE_URL}/rest/v1/venues?id=eq.${r.id}`, {
        method: "PATCH",
        headers: { ...HEADERS, Prefer: "return=minimal" },
        body: JSON.stringify({ field_sources: sources }),
      });
      if (!res.ok) console.warn(`  ${r.name}: ${res.status} ${(await res.text()).slice(0, 90)}`);
    }
  }

  console.log(`venues given provenance: ${touched}`);
  for (const [field, count] of Object.entries(tally).sort((a, b) => b[1] - a[1])) {
    console.log(`   ${field.padEnd(14)} ${count}`);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});

export {};
