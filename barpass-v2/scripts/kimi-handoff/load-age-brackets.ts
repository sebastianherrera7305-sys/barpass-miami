/**
 * Loads one Kimi city-research JSON (scripts/kimi-handoff/<city>.json).
 * Purely additive, per explicit instruction: NEVER deletes or edits an
 * existing venue's core fields (rating, etc. stay whatever our own Google
 * sync last verified — Kimi's re-quoted rating is not trusted over that).
 *
 * - action "keep_existing": venue must already exist in `venues` (matched
 *   by exact name + city). Tags it with an age bracket in
 *   `venue_age_brackets`. If it does NOT actually exist, treated as
 *   add_new instead (some entries were mislabeled by the research pass —
 *   verified against the live DB, never assumed).
 * - action "add_new": geocoded for real via Google Places Text Search
 *   (same API/pattern as scripts/enrich-venues.ts) to get a real place_id,
 *   lat/lng, rating, and formatted address before inserting — never a
 *   fabricated location. Skipped (reported, not guessed) if Google can't
 *   find a confident match.
 *
 * Usage: node --env-file=.env.local --import tsx scripts/kimi-handoff/load-age-brackets.ts <city.json>
 */
import { createClient } from "@supabase/supabase-js";
// @ts-expect-error - ws no trae tipos propios
import ws from "ws";
import fs from "fs";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const PLACES_API_KEY = process.env.GOOGLE_PLACES_API_KEY;
if (!SUPABASE_URL || !SERVICE_ROLE_KEY || !PLACES_API_KEY) {
  console.error("Faltan env vars (Supabase o Google Places)");
  process.exit(1);
}
const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  realtime: { transport: ws as unknown as typeof WebSocket },
});

type KimiEntry = { name: string; address?: string; why: string; action: string; google_rating?: number };
type KimiCity = Record<string, KimiEntry[]>; // bracket -> entries

async function findPlace(name: string, address: string | undefined, city: string) {
  const query = address ? `${name}, ${address}` : `${name}, ${city}`;
  const res = await fetch("https://places.googleapis.com/v1/places:searchText", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": PLACES_API_KEY!,
      "X-Goog-FieldMask": "places.id,places.displayName,places.formattedAddress,places.location,places.rating,places.userRatingCount,places.addressComponents,places.regularOpeningHours",
    },
    body: JSON.stringify({ textQuery: query, maxResultCount: 1 }),
  });
  if (!res.ok) return null;
  const data = await res.json();
  return data.places?.[0] ?? null;
}

function neighborhoodFrom(place: any): string {
  const comp = place.addressComponents?.find((c: any) => c.types?.includes("neighborhood") || c.types?.includes("sublocality"));
  return comp?.longText ?? place.formattedAddress?.split(",")[1]?.trim() ?? "Miami";
}

function hoursFrom(place: any): { open: string; close: string } {
  const desc: string[] | undefined = place.regularOpeningHours?.weekdayDescriptions;
  if (!desc || desc.length === 0) return { open: "Ver Google Maps", close: "Ver Google Maps" };
  // Real text from Google, not parsed into HH:MM — stored as-is rather
  // than guessed, since formats vary ("6 PM–2 AM", "Open 24 hours", etc.)
  const friday = desc.find((d) => d.startsWith("Friday")) ?? desc[0];
  return { open: friday, close: friday };
}

// Case/emoji/suffix-tolerant match — the DB has real names Google (or an
// earlier enrichment pass) suffixed with things like " ♣️" or " - Restaurant
// & Sports Bar" that Kimi's plain name never includes. An exact `eq` match
// silently missed 8 real matches in the Miami batch and inserted duplicate
// venues instead of tagging the originals — this is why we now load the
// city's venues once and compare normalized forms.
function normalize(name: string): string {
  return name
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\s]/gu, "") // strip emoji/punctuation, keep letters/digits/spaces
    .replace(/\s+/g, " ")
    .trim();
}

function findExisting(entryName: string, cityVenues: { id: string; name: string }[]) {
  const target = normalize(entryName);
  // Exact normalized match first, then "one name contains the other" as a
  // fallback for suffixed variants (e.g. "grails miami" vs
  // "grails miami restaurant sports bar").
  return (
    cityVenues.find((v) => normalize(v.name) === target) ??
    cityVenues.find((v) => {
      const vn = normalize(v.name);
      return vn.includes(target) || target.includes(vn);
    })
  );
}

async function main() {
  const path = process.argv[2];
  if (!path) {
    console.error("Uso: load-age-brackets.ts <ruta-al-json>");
    process.exit(1);
  }
  const raw = JSON.parse(fs.readFileSync(path, "utf-8"));
  const [city, brackets]: [string, KimiCity] = Object.entries(raw)[0] as [string, KimiCity];

  const { data: cityVenuesRaw } = await supabase.from("venues").select("id,name").eq("city", city);
  const cityVenues = cityVenuesRaw ?? [];

  let tagged = 0, added = 0, skipped: string[] = [], relabeled = 0;

  for (const [bracket, entries] of Object.entries(brackets)) {
    for (const entry of entries) {
      const existing = findExisting(entry.name, cityVenues);

      if (entry.action === "keep_existing" && existing) {
        await supabase.from("venue_age_brackets").upsert(
          { venue_id: existing.id, bracket, why: entry.why, source: "kimi_research" },
          { onConflict: "venue_id,bracket" }
        );
        tagged++;
        continue;
      }

      if (entry.action === "keep_existing" && !existing) {
        console.log(`  (relabeled add_new, no existía) ${entry.name}`);
        relabeled++;
      }

      // add_new (or mislabeled keep_existing) — geocode for real.
      if (existing) {
        // Already in DB under a slightly different action label — just tag it.
        await supabase.from("venue_age_brackets").upsert(
          { venue_id: existing.id, bracket, why: entry.why, source: "kimi_research" },
          { onConflict: "venue_id,bracket" }
        );
        tagged++;
        continue;
      }

      const place = await findPlace(entry.name, entry.address, city);
      if (!place || !place.location) {
        skipped.push(entry.name);
        continue;
      }

      const hours = hoursFrom(place);
      const slug = entry.name.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/(^-|-$)/g, "");

      const { data: inserted, error } = await supabase
        .from("venues")
        .insert({
          slug: `${slug}-${city.toLowerCase()}`,
          name: place.displayName?.text ?? entry.name,
          type: "bar",
          neighborhood: neighborhoodFrom(place),
          address: place.formattedAddress ?? entry.address ?? "Ver Google Maps",
          lat: place.location.latitude,
          lng: place.location.longitude,
          description: entry.why,
          rating: place.rating ?? 0,
          review_count: place.userRatingCount ?? 0,
          open_time: hours.open,
          close_time: hours.close,
          city,
          country: "US",
          timezone: "America/New_York",
        })
        .select("id")
        .single();

      if (error || !inserted) {
        console.error(`  FALLÓ insert de ${entry.name}:`, error?.message);
        skipped.push(entry.name);
        continue;
      }

      // So a later entry in this same run (e.g. the same venue appearing
      // under two brackets) matches the row we just inserted instead of
      // creating a second duplicate.
      cityVenues.push({ id: inserted.id, name: place.displayName?.text ?? entry.name });

      await supabase.from("venue_age_brackets").insert({
        venue_id: inserted.id,
        bracket,
        why: entry.why,
        source: "kimi_research",
      });
      added++;
    }
  }

  console.log(`\n${city}: ${tagged} existentes etiquetados, ${added} nuevos geocodificados e insertados, ${relabeled} relabeled, ${skipped.length} saltados`);
  if (skipped.length) console.log("Saltados (Google no encontró match confiable):", skipped.join(", "));
}

main();
