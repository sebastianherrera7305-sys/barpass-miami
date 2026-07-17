/**
 * Populates venue_experience_tags from data already in `venues` — no
 * external API calls, no Google Places requests, no cost. Pure derivation
 * via the rule engine in experience-tags-rules.ts.
 *
 * Uso: npm run derive-tags [-- --dry-run] [-- --only=slug1,slug2]
 * Requiere: NEXT_PUBLIC_SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (mismas env
 * vars que enrich-venues.ts).
 */
import { createClient } from "@supabase/supabase-js";
// @ts-expect-error — ver la misma nota en enrich-venues.ts
import ws from "ws";
import { deriveExperienceTags, type VenueSignals } from "./experience-tags-rules";

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
const dryRun = args.includes("--dry-run");
const onlyArg = args.find((a) => a.startsWith("--only="));
const onlySlugs = onlyArg ? onlyArg.replace("--only=", "").split(",") : null;

interface VenueRow extends VenueSignals {
  id: string;
  slug: string;
  name: string;
  happy_hour_until: string | null;
  wheelchair_accessible: boolean | null;
  outdoor_seating: boolean | null;
  good_for_groups: boolean | null;
  good_for_watching_sports: boolean | null;
  has_live_music: boolean | null;
  serves_vegetarian_food: boolean | null;
}

async function main() {
  let query = supabase
    .from("venues")
    .select(
      "id,slug,name,type,happy_hour_until,wheelchair_accessible,outdoor_seating,good_for_groups,good_for_watching_sports,has_live_music,reservable,serves_vegetarian_food"
    );
  if (onlySlugs) query = query.in("slug", onlySlugs);

  const { data: venues, error } = await query;
  if (error || !venues) {
    console.error("No se pudieron leer los venues:", error?.message);
    process.exit(1);
  }

  console.log(`Derivando experience tags para ${venues.length} venues${dryRun ? " (dry-run)" : ""}...`);

  for (const row of venues as unknown as VenueRow[]) {
    const tags = deriveExperienceTags({
      type: row.type,
      hasHappyHour: !!row.happy_hour_until,
      wheelchairAccessible: row.wheelchair_accessible,
      outdoorSeating: row.outdoor_seating,
      goodForGroups: row.good_for_groups,
      goodForWatchingSports: row.good_for_watching_sports,
      hasLiveMusic: row.has_live_music,
      reservable: row.reservable,
      servesVegetarianFood: row.serves_vegetarian_food,
    });

    console.log(`\n${row.name} (${row.slug}): ${tags.map((t) => t.id).join(", ") || "(sin tags)"}`);

    if (dryRun) continue;

    // Replace this venue's tags atomically rather than upserting individual
    // rows — a rule that no longer applies (e.g. an amenity flag changed)
    // must not leave a stale tag behind.
    await supabase.from("venue_experience_tags").delete().eq("venue_id", row.id);
    if (tags.length > 0) {
      const { error: insertError } = await supabase.from("venue_experience_tags").insert(
        tags.map((t) => ({
          venue_id: row.id,
          tag_id: t.id,
          category: t.category,
          confidence: t.confidence,
          source: t.source,
        }))
      );
      if (insertError) console.error(`  ERROR guardando tags: ${insertError.message}`);
    }
  }

  console.log(dryRun ? "\n(--dry-run: no se escribió nada)" : "\nListo.");
}

main();
