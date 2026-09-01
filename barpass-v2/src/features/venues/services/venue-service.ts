import type { Venue, Neighborhood, VenueEvent } from "@/types";
import { isSupabaseConfigured } from "@/lib/supabase/config";
import { VENUES } from "../data/venues";

/**
 * Venue data access layer.
 *
 * Every venue read in the app goes through this module — pages, the AI
 * concierge, the map, and collections all call these functions. Reads from
 * Supabase when configured, falls back to the local catalog otherwise.
 */

// ── Data-source honesty ───────────────────────────────────────
// Antes, si Supabase fallaba o no estaba configurado, el catálogo local
// hardcodeado (VENUES) se servía en silencio como si fuera data real y
// actualizada — el usuario no tenía forma de saber que veía precios/horarios
// desactualizados. Este flag lo expone para que la UI pueda avisar.
let _isServingLiveData = true;
export function isServingLiveData(): boolean {
  return _isServingLiveData;
}

// ── Supabase helpers ──────────────────────────────────────────

interface DbVenue {
  id: string;
  slug: string;
  name: string;
  type: Venue["type"];
  neighborhood: Venue["neighborhood"];
  address: string;
  lat: number;
  lng: number;
  hook: string;
  description: string;
  rating: number;
  review_count: number;
  cover_men: number | null;
  cover_women: number | null;
  price_tier: number;
  avg_spend: number;
  open_time: string;
  close_time: string;
  happy_hour_until: string | null;
  music_genres: Venue["musicGenres"];
  vibes: string[];
  dress_code: string;
  parking: string;
  crowd_level: Venue["crowdLevel"];
  best_arrival_time: string;
  peak_hours: string;
  popular_drinks: Venue["popularDrinks"];
  emoji: string;
  image_url: string | null;
  instagram_handle: string | null;
  is_trending: boolean;
}

/**
 * popular_drinks is stored in Supabase as a JSON-encoded STRING (legacy of
 * the seed script), not a jsonb array — same quirk the iOS decoder handles.
 * Accept both shapes and never crash a page over it.
 */
function parseDrinks(raw: unknown): Venue["popularDrinks"] {
  let arr: unknown = raw;
  if (typeof raw === "string") {
    try { arr = JSON.parse(raw); } catch { return []; }
  }
  if (!Array.isArray(arr)) return [];
  return arr
    .filter((d): d is Record<string, unknown> => !!d && typeof d === "object")
    .map((d) => ({
      name: String(d.name ?? ""),
      price: Number(d.price ?? 0),
      emoji: String(d.emoji ?? "🍸"),
    }))
    .filter((d) => d.name.length > 0);
}

function mapDbVenue(v: DbVenue): Venue {
  return {
    id: v.id,
    slug: v.slug,
    name: v.name,
    type: v.type,
    neighborhood: v.neighborhood,
    address: v.address,
    lat: v.lat,
    lng: v.lng,
    hook: v.hook,
    description: v.description,
    rating: v.rating,
    reviewCount: v.review_count,
    coverMen: v.cover_men,
    coverWomen: v.cover_women,
    priceTier: v.price_tier as Venue["priceTier"],
    avgSpend: v.avg_spend,
    openTime: v.open_time,
    closeTime: v.close_time,
    happyHourUntil: v.happy_hour_until,
    musicGenres: v.music_genres,
    vibes: v.vibes,
    dressCode: v.dress_code,
    parking: v.parking,
    crowdLevel: v.crowd_level,
    bestArrivalTime: v.best_arrival_time,
    peakHours: v.peak_hours,
    popularDrinks: parseDrinks(v.popular_drinks),
    emoji: v.emoji,
    imageUrl: v.image_url,
    instagramHandle: v.instagram_handle,
    isTrending: v.is_trending,
    isOpenNow: false,
    upcomingEvents: [],
  };
}

interface DbEvent {
  id: string;
  venue_id: string;
  title: string;
  description: string;
  starts_at: string;
  ends_at: string | null;
  cover_price: number | null;
}

// ── Cache ─────────────────────────────────────────────────────
// One page render calls getVenues/getTrending/getHappyHour/etc., each of
// which used to hit Supabase again (~10 identical queries per view). A
// module-level TTL cache + in-flight dedup collapses that to one fetch per
// minute per server instance. Venue data changes rarely; 60s staleness is
// invisible to users.

const CACHE_TTL_MS = 60_000;
let venueCache: { data: Venue[]; ts: number } | null = null;
let inFlight: Promise<Venue[]> | null = null;

async function fetchVenues(): Promise<Venue[]> {
  if (venueCache && Date.now() - venueCache.ts < CACHE_TTL_MS) {
    return venueCache.data;
  }
  if (inFlight) return inFlight;
  inFlight = fetchVenuesUncached()
    .then((data) => {
      venueCache = { data, ts: Date.now() };
      return data;
    })
    .finally(() => {
      inFlight = null;
    });
  return inFlight;
}

/** PostgREST's hard per-response row cap. */
const REST_PAGE_SIZE = 1000;
/** Safety stop so a server that always returns a full page can't spin forever. */
const REST_MAX_PAGES = 20;

/**
 * Plain-fetch REST read (same pattern as the iOS app), following PostgREST's
 * pagination instead of silently stopping at the first page.
 *
 * We deliberately avoid both supabase clients here: the cookie-bound one
 * throws inside generateStaticParams, and supabase-js hits a Node stream bug
 * under Next 16 dev that turned 200ms queries into 15s+. Venues/events are
 * public data — an apikey header is all that's needed.
 *
 * Paging matters because the 1000-row cap is not an error: the request
 * succeeds and returns a truncated array. `venues` (1846 rows) was quietly
 * reduced to the alphabetical first 1000, and everything after that simply
 * did not exist for the web app — no detail page (`getVenueBySlug` 404'd),
 * no map pin, no search hit. `SupabaseVenueRepository` on iOS already pages
 * this way; the web never got the same treatment.
 *
 * No cache directive on the fetch: "no-store" here forbids static
 * prerendering and silently downgraded /venues/[slug] to the local fallback
 * at build time. Freshness at runtime is handled by the module-level TTL
 * cache above.
 */
async function restGetAll<T>(path: string): Promise<T[]> {
  const { getSupabaseEnv } = await import("@/lib/supabase/config");
  const env = getSupabaseEnv()!;
  const all: T[] = [];

  for (let page = 0; page < REST_MAX_PAGES; page++) {
    const from = page * REST_PAGE_SIZE;
    const res = await fetch(`${env.url}/rest/v1/${path}`, {
      headers: {
        apikey: env.anonKey,
        Authorization: `Bearer ${env.anonKey}`,
        "Range-Unit": "items",
        Range: `${from}-${from + REST_PAGE_SIZE - 1}`,
      },
      signal: AbortSignal.timeout(10_000),
    });
    if (!res.ok) throw new Error(`Supabase REST ${res.status} on ${path}`);

    const rows = (await res.json()) as T[];
    all.push(...rows);
    if (rows.length < REST_PAGE_SIZE) break;
  }

  return all;
}

async function fetchVenuesUncached(): Promise<Venue[]> {
  if (!isSupabaseConfigured()) {
    _isServingLiveData = false;
    return VENUES;
  }
  try {
    // excluded_reason: "should this be in a nightlife app at all" (airport
    // lounges, a cinema, smoke shops, venues 40km+ outside Miami — see
    // supabase/venue_exclusions.sql). business_status: "does it still
    // exist". Both columns existed and neither was filtered, so the
    // catalogue served places nobody could go out to.
    const data = await restGetAll<DbVenue>(
      // The or(...) is deliberate: `business_status <> 'CLOSED_PERMANENTLY'`
      // is NULL — not true — for the 171 venues Google enrichment never
      // reached, so a bare not.eq silently dropped them. Missing data must
      // never read as "closed".
      "venues?select=*&excluded_reason=is.null" +
        "&or=(business_status.is.null,business_status.neq.CLOSED_PERMANENTLY)" +
        "&order=name",
    );
    const venues = data.map(mapDbVenue);
    _isServingLiveData = true;

    try {
      const eventData = await restGetAll<DbEvent>("events?select=*&order=starts_at");
      const byVenue = new Map<string, VenueEvent[]>();
      for (const e of eventData) {
        const list = byVenue.get(e.venue_id) ?? [];
        list.push({
          id: e.id,
          title: e.title,
          date: e.starts_at,
          endDate: e.ends_at,
          coverPrice: e.cover_price,
          description: e.description,
        });
        byVenue.set(e.venue_id, list);
      }
      for (const venue of venues) {
        venue.upcomingEvents = byVenue.get(venue.id) ?? [];
      }
    } catch (eventErr) {
      console.warn("Supabase event fetch failed, venues shown without events:", eventErr);
    }

    return venues;
  } catch (e) {
    console.warn("Supabase venue fetch failed, falling back to local:", e);
    _isServingLiveData = false;
    return VENUES;
  }
}

// ── Public API ────────────────────────────────────────────────

export async function getVenues(): Promise<Venue[]> {
  return fetchVenues();
}

export async function getVenueBySlug(slug: string): Promise<Venue | null> {
  const venues = await fetchVenues();
  return venues.find((v) => v.slug === slug) ?? null;
}

export async function getTrendingVenues(): Promise<Venue[]> {
  const venues = await fetchVenues();
  return venues.filter((v) => v.isTrending);
}

export async function getHappyHourVenues(): Promise<Venue[]> {
  const venues = await fetchVenues();
  return venues.filter((v) => v.happyHourUntil !== null);
}

export async function getVenuesByNeighborhood(): Promise<
  Map<Neighborhood, Venue[]>
> {
  const venues = await fetchVenues();
  const grouped = new Map<Neighborhood, Venue[]>();
  for (const venue of venues) {
    const list = grouped.get(venue.neighborhood) ?? [];
    list.push(venue);
    grouped.set(venue.neighborhood, list);
  }
  return grouped;
}

export interface VenueEventEntry {
  venueName: string;
  venueSlug: string;
  venueEmoji: string;
  event: VenueEvent;
}

export async function getAllEvents(): Promise<VenueEventEntry[]> {
  const venues = await fetchVenues();
  const entries: VenueEventEntry[] = [];
  for (const venue of venues) {
    for (const event of venue.upcomingEvents) {
      entries.push({ venueName: venue.name, venueSlug: venue.slug, venueEmoji: venue.emoji, event });
    }
  }
  return entries.sort((a, b) => new Date(a.event.date).getTime() - new Date(b.event.date).getTime());
}

export async function getSimilarVenues(venue: Venue, limit = 3): Promise<Venue[]> {
  const venues = await fetchVenues();
  return venues.filter(
    (v) =>
      v.id !== venue.id &&
      (v.type === venue.type || v.neighborhood === venue.neighborhood),
  ).slice(0, limit);
}
