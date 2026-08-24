/**
 * Loads a Kimi stadium-research JSON (scripts/kimi-handoff/<stadium>.json,
 * shape from BRIEF-hard-rock-stadium.md Fase 1) into stadiums/stadium_pois.
 * Never invents anything — every POI keeps its own real source_url and
 * confidence exactly as researched.
 *
 * Usage: node --env-file=.env.local --import tsx scripts/kimi-handoff/load-stadium.ts <file.json> <lat> <lng>
 */
import { createClient } from "@supabase/supabase-js";
// @ts-expect-error - ws no trae tipos propios
import ws from "ws";
import fs from "fs";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
  console.error("Faltan env vars");
  process.exit(1);
}
const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  realtime: { transport: ws as unknown as typeof WebSocket },
});

type Poi = { name: string; type: string; section_or_concourse: string; source_url: string; confidence: string };
type Level = { name: string; pois: Poi[] };
type StadiumJson = { stadium: string; address: string; levels: Level[] };

// Kimi's POI "type" values map 1:1 to the check constraint except these two.
function normalizeType(t: string): string {
  if (t === "other") return "other";
  const allowed = ["bar", "concession", "merch", "restroom", "first_aid", "guest_services", "elevator", "entrance", "other"];
  return allowed.includes(t) ? t : "other";
}

async function main() {
  const [path, latStr, lngStr] = process.argv.slice(2);
  if (!path || !latStr || !lngStr) {
    console.error("Uso: load-stadium.ts <file.json> <lat> <lng>");
    process.exit(1);
  }
  const data: StadiumJson = JSON.parse(fs.readFileSync(path, "utf-8"));

  const { data: stadium, error: stadiumError } = await supabase
    .from("stadiums")
    .upsert(
      {
        name: data.stadium,
        address: data.address,
        lat: parseFloat(latStr),
        lng: parseFloat(lngStr),
        source_url: "https://www.hardrockstadium.com/a-z-guide/",
      },
      { onConflict: "name" }
    )
    .select("id")
    .single();

  if (stadiumError || !stadium) {
    console.error("FALLÓ insert de stadium:", stadiumError?.message);
    process.exit(1);
  }

  let inserted = 0;
  for (const [levelOrder, level] of data.levels.entries()) {
    // Skip "we know this exists but have zero location info" placeholders
    // (Kimi's restroom entries: type=restroom with an explicit UNKNOWN
    // section) — a POI list entry with no actual location tells the user
    // nothing, it would just be visual noise.
    const rows = level.pois
      .filter((poi) => !(poi.type === "restroom" && poi.section_or_concourse?.startsWith("UNKNOWN")))
      .map((poi) => ({
      stadium_id: stadium.id,
      level_name: level.name,
      level_order: levelOrder,
      name: poi.name,
      poi_type: normalizeType(poi.type),
      section_or_concourse: poi.section_or_concourse?.startsWith("UNKNOWN") ? null : poi.section_or_concourse,
      source_url: poi.source_url,
      confidence: poi.confidence === "unverified" ? "unverified" : "verified",
    }));
    if (rows.length === 0) continue;
    const { error } = await supabase.from("stadium_pois").insert(rows);
    if (error) {
      console.error(`FALLÓ insert de POIs en ${level.name}:`, error.message);
      continue;
    }
    inserted += rows.length;
    console.log(`${level.name}: ${rows.length} POIs`);
  }

  console.log(`\nTotal: ${inserted} POIs cargados para ${data.stadium}`);
}

main();
