/**
 * Merges the researched greek-research/batch-*.json files and writes them
 * to Supabase (universities + greek_chapters). Every chapter already
 * carries a real official_source_url from the research pass — this script
 * does no research/invention of its own, just loads what was verified.
 *
 * Uso: node --env-file=.env.local --import tsx scripts/load-greek-life.ts
 */
import { createClient } from "@supabase/supabase-js";
// @ts-expect-error - ws no trae tipos propios
import ws from "ws";
import fs from "fs";
import path from "path";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
  console.error("Faltan env vars");
  process.exit(1);
}
const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  realtime: { transport: ws as unknown as typeof WebSocket },
});

const dir = path.join(__dirname, "greek-research");
const files = fs.readdirSync(dir).filter((f) => f.endsWith(".json"));

let totalUnis = 0;
let totalChapters = 0;
let needsReview = 0;

async function main() {
  for (const file of files) {
    const data = JSON.parse(fs.readFileSync(path.join(dir, file), "utf-8"));
    for (const uni of data.universities) {
      const { data: uniRow, error: uniErr } = await supabase
        .from("universities")
        .upsert(
          {
            name: uni.name,
            short_name: uni.short_name ?? null,
            city: uni.city,
            state: uni.state ?? null,
            country: uni.country ?? "US",
            official_url: uni.official_url ?? null,
            greek_life_url: uni.greek_life_url ?? null,
            party_life_notes: uni.party_life_notes ?? null,
            source_last_verified: new Date().toISOString(),
          },
          { onConflict: "name,city" }
        )
        .select("id")
        .single();

      if (uniErr || !uniRow) {
        console.error(`FALLÓ universidad ${uni.name}:`, uniErr?.message);
        continue;
      }
      totalUnis++;

      const chapterRows = (uni.chapters ?? []).map((c: any) => ({
        university_id: uniRow.id,
        fraternity_name: c.fraternity_name,
        chapter_designation: c.chapter_designation ?? null,
        council: c.council,
        status: c.status ?? "unknown",
        official_source_url: c.official_source_url,
        chapter_url: c.chapter_url ?? null,
        address: c.address ?? null,
        lat: c.lat ?? null,
        lng: c.lng ?? null,
        address_verified: c.address_verified ?? false,
        needs_review: c.needs_review ?? false,
        review_reason: c.review_reason ?? null,
        source_last_verified: new Date().toISOString(),
      }));

      if (chapterRows.length > 0) {
        const { error: chErr } = await supabase.from("greek_chapters").insert(chapterRows);
        if (chErr) {
          console.error(`FALLÓ capítulos de ${uni.name}:`, chErr.message);
          continue;
        }
        totalChapters += chapterRows.length;
        needsReview += chapterRows.filter((c: any) => c.needs_review).length;
      }
      console.log(`  ${uni.name}: ${chapterRows.length} capítulos`);
    }
  }
  console.log(`\nListo. universidades=${totalUnis} capítulos=${totalChapters} needs_review=${needsReview}`);
}

main();
