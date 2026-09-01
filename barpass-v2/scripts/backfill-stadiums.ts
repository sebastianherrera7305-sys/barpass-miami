/**
 * Brings every stadium up to the level of detail Hard Rock already has.
 *
 * TestFlight: "otros estadios necesitan tener toda la info igual al hard
 * rock". Hard Rock carries a photo, a description and a seat map; of the 22
 * stadiums, 16 had no seat map and 4 had no description, so the others looked
 * half-finished by comparison.
 *
 * Both gaps are filled from the same real sources the app already uses:
 *   - seat map    → Ticketmaster, `event.seatmap.staticUrl` for an event at
 *                   that venue. The seating geometry is venue-wide, so one
 *                   event's image stands in for "the stadium's map".
 *   - description → Google Places editorialSummary.
 *
 * Nothing is written that a source did not return. A stadium Ticketmaster has
 * no events for keeps a null seat map rather than borrowing another venue's.
 *
 * Usage:
 *   npx tsx scripts/backfill-stadiums.ts --dry-run
 *   npx tsx scripts/backfill-stadiums.ts
 */

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const TM_KEY = process.env.TICKETMASTER_API_KEY;
const PLACES_KEY = process.env.GOOGLE_PLACES_API_KEY;

if (!SUPABASE_URL || !SERVICE_KEY) throw new Error("Missing Supabase env vars");
if (!TM_KEY) throw new Error("Missing TICKETMASTER_API_KEY");
if (!PLACES_KEY) throw new Error("Missing GOOGLE_PLACES_API_KEY");

const DRY_RUN = process.argv.includes("--dry-run");

const REST_HEADERS = {
  apikey: SERVICE_KEY,
  Authorization: `Bearer ${SERVICE_KEY}`,
  "Content-Type": "application/json",
};

interface Stadium {
  id: string;
  name: string;
  address: string;
  seatmap_url: string | null;
  description: string | null;
  image_url: string | null;
}

/** "1060 West Addison Street, Chicago, IL 60613" → "Chicago" */
function cityFrom(address: string): string | null {
  const parts = address.split(",").map((p) => p.trim());
  return parts.length >= 3 ? parts[parts.length - 2] : null;
}

async function json<T>(url: string, init?: RequestInit): Promise<T | null> {
  try {
    const res = await fetch(url, init);
    if (!res.ok) return null;
    return (await res.json()) as T;
  } catch {
    return null;
  }
}

interface TMEvent {
  seatmap?: { staticUrl?: string };
}

/**
 * Ticketmaster's venue search is fuzzy, so the city is used to disambiguate —
 * "Wrigley Field" alone returns a second, unrelated venue with no city set.
 */
async function seatmapFor(stadium: Stadium): Promise<string | null> {
  const city = cityFrom(stadium.address);
  const venueSearch = await json<{ _embedded?: { venues?: { id: string; city?: { name?: string } }[] } }>(
    `https://app.ticketmaster.com/discovery/v2/venues.json` +
      `?keyword=${encodeURIComponent(stadium.name)}&apikey=${TM_KEY}`,
  );
  const venues = venueSearch?._embedded?.venues ?? [];
  const match =
    venues.find((v) => city && v.city?.name?.toLowerCase() === city.toLowerCase()) ?? venues[0];
  if (!match) return null;

  const events = await json<{ _embedded?: { events?: TMEvent[] } }>(
    `https://app.ticketmaster.com/discovery/v2/events.json` +
      `?venueId=${match.id}&size=20&apikey=${TM_KEY}`,
  );
  for (const event of events?._embedded?.events ?? []) {
    if (event.seatmap?.staticUrl) return event.seatmap.staticUrl;
  }
  return null;
}

async function descriptionFor(stadium: Stadium): Promise<string | null> {
  const search = await json<{ places?: { id: string }[] }>(
    "https://places.googleapis.com/v1/places:searchText",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": PLACES_KEY!,
        "X-Goog-FieldMask": "places.id",
      },
      body: JSON.stringify({ textQuery: `${stadium.name}, ${stadium.address}`, maxResultCount: 1 }),
    },
  );
  const placeId = search?.places?.[0]?.id;
  if (!placeId) return null;

  const details = await json<{ editorialSummary?: { text?: string } }>(
    `https://places.googleapis.com/v1/places/${placeId}`,
    { headers: { "X-Goog-Api-Key": PLACES_KEY!, "X-Goog-FieldMask": "editorialSummary" } },
  );
  return details?.editorialSummary?.text ?? null;
}

async function main() {
  const res = await fetch(
    `${SUPABASE_URL}/rest/v1/stadiums?select=id,name,address,seatmap_url,description,image_url&order=name`,
    { headers: REST_HEADERS },
  );
  const stadiums = (await res.json()) as Stadium[];
  console.log(`${stadiums.length} stadiums${DRY_RUN ? " (dry run)" : ""}\n`);

  let maps = 0, descs = 0;

  for (const s of stadiums) {
    const update: Record<string, unknown> = {};

    if (!s.seatmap_url) {
      const url = await seatmapFor(s);
      if (url) { update.seatmap_url = url; maps++; }
    }
    if (!s.description) {
      const text = await descriptionFor(s);
      if (text) { update.description = text; descs++; }
    }

    const changed = Object.keys(update);
    console.log(
      `${s.name.slice(0, 34).padEnd(36)} ${changed.length ? "+ " + changed.join(", ") : "already complete"}`,
    );

    if (changed.length && !DRY_RUN) {
      const up = await fetch(`${SUPABASE_URL}/rest/v1/stadiums?id=eq.${s.id}`, {
        method: "PATCH",
        headers: { ...REST_HEADERS, Prefer: "return=minimal" },
        body: JSON.stringify(update),
      });
      if (!up.ok) console.warn(`   update failed: ${up.status} ${(await up.text()).slice(0, 100)}`);
    }
  }

  console.log(`\nseat maps added: ${maps}   descriptions added: ${descs}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});

// Marks this file a module. Without it TypeScript treats a script with no
// imports as a global script, and these two both declare SUPABASE_URL at top
// level — "Cannot redeclare block-scoped variable", which fails next build.
export {};
