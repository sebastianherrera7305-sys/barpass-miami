/**
 * What a venue owner sees about their OWN venue — the same catalogue row the
 * apps read, narrowed to an explicit DTO.
 *
 * Two rules from CLAUDE.md shape this file:
 *
 * 1. Every venue read filters `excluded_reason` and `business_status`. The
 *    owner view is the one place where filtering the row OUT would be the
 *    wrong answer: if their venue is hidden, they need to be TOLD that, and
 *    why. So the filter becomes a visibility verdict instead of a WHERE
 *    clause — see `listingVisibility`.
 * 2. An empty value is a fact; a guessed one is a lie. Nothing here invents a
 *    default. Unknown hours are `null`, not "closed". Unknown amenities are
 *    `null`, not `false`. `avg_spend = 0` means "no data", not "$0".
 */

/** Row shape as stored: `[{"day":5,"open":"20:00","close":"02:00"}]`, day 0 = Sunday
 *  (Google's numbering), and the day is the day it OPENS — a close earlier than
 *  the open just means it closes the next morning, the normal nightlife case.
 *  See scripts/backfill-venue-hours.ts. A day with no entry is CLOSED that day;
 *  a venue with no `hours` at all is UNKNOWN, which is not the same thing. */
export interface RawDayHours {
  day: number;
  open: string;
  close: string;
}

export interface OwnerDayHours {
  /** 0 = Sunday. */
  day: number;
  label: string;
  /** Empty when the venue is closed that day. A day can legitimately have two. */
  periods: Array<{ open: string; close: string }>;
  closed: boolean;
}

const DAY_LABELS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
/** Presented Monday-first: a nightlife week reads Mon → Sun, not Sun → Sat. */
const WEEK_ORDER = [1, 2, 3, 4, 5, 6, 0];
const HHMM = /^([01]\d|2[0-3]):[0-5]\d$/;

/**
 * Returns null — "we don't know this venue's hours" — rather than seven closed
 * days, whenever the column is absent, empty, or unparseable. 171 venues in the
 * catalogue were never reached by Google enrichment; rendering them as "closed
 * all week" on their owner's own dashboard would be a fabricated fact.
 */
export function toWeeklyHours(raw: unknown): OwnerDayHours[] | null {
  let parsed: unknown = raw;
  if (typeof raw === "string") {
    try {
      parsed = JSON.parse(raw);
    } catch {
      return null;
    }
  }
  if (!Array.isArray(parsed) || parsed.length === 0) return null;

  const byDay = new Map<number, Array<{ open: string; close: string }>>();
  for (const entry of parsed) {
    if (!entry || typeof entry !== "object") continue;
    const e = entry as Record<string, unknown>;
    const day = Number(e.day);
    const open = typeof e.open === "string" ? e.open : "";
    const close = typeof e.close === "string" ? e.close : "";
    if (!Number.isInteger(day) || day < 0 || day > 6) continue;
    if (!HHMM.test(open) || !HHMM.test(close)) continue;
    const list = byDay.get(day) ?? [];
    list.push({ open, close });
    byDay.set(day, list);
  }
  if (byDay.size === 0) return null;

  return WEEK_ORDER.map((day) => {
    const periods = (byDay.get(day) ?? []).sort((a, b) => a.open.localeCompare(b.open));
    return { day, label: DAY_LABELS[day], periods, closed: periods.length === 0 };
  });
}

export interface ListingVisibility {
  /** Is this venue served to the apps right now? */
  listed: boolean;
  /** Plain-language why-not. Null when listed. */
  reason: string | null;
  /** Google's value, verbatim. Null means Google enrichment never reached it —
   *  which is NOT "closed", and is why every read uses `or=(is.null,neq.…)`. */
  businessStatus: string | null;
}

export function listingVisibility(row: {
  excluded_reason?: string | null;
  business_status?: string | null;
}): ListingVisibility {
  const businessStatus = row.business_status ?? null;
  if (row.excluded_reason) {
    return { listed: false, reason: row.excluded_reason, businessStatus };
  }
  if (businessStatus === "CLOSED_PERMANENTLY") {
    return {
      listed: false,
      reason: "Google reports this venue as permanently closed, so BarPass stops serving it.",
      businessStatus,
    };
  }
  return { listed: true, reason: null, businessStatus };
}

/** Tri-state on purpose: null is "nobody has checked", not "no". */
export interface OwnerAmenities {
  outdoorSeating: boolean | null;
  goodForGroups: boolean | null;
  goodForWatchingSports: boolean | null;
  hasLiveMusic: boolean | null;
  reservable: boolean | null;
  restroom: boolean | null;
  servesVegetarianFood: boolean | null;
  wheelchairAccessible: boolean | null;
}

export interface OwnerVenueRow {
  id: string;
  slug: string;
  name: string;
  type: string;
  city: string | null;
  neighborhood: string | null;
  address: string | null;
  phone: string | null;
  website: string | null;
  instagram_handle: string | null;
  image_url: string | null;
  age_policy: string | null;
  price_tier: number | null;
  avg_spend: number | null;
  cover_men: number | null;
  cover_women: number | null;
  open_time: string | null;
  close_time: string | null;
  happy_hour_until: string | null;
  dress_code: string | null;
  parking: string | null;
  timezone: string | null;
  music_genres: string[] | null;
  vibes: string[] | null;
  hours: unknown;
  popular_drinks: unknown;
  field_sources: Record<string, { url?: unknown; date?: unknown; at?: unknown } | undefined> | null;
  excluded_reason: string | null;
  business_status: string | null;
  google_synced_at: string | null;
  [key: string]: unknown;
}

export interface OwnerDrink {
  name: string;
  price: number;
  emoji: string;
}

/**
 * Same rule the public site uses: an item without a positive price is dropped,
 * never rendered as a confident "$0". Stored as a JSON-encoded string on some
 * rows (a legacy of the seed script), so both shapes are accepted.
 */
export function parseOwnerDrinks(raw: unknown): OwnerDrink[] {
  let arr: unknown = raw;
  if (typeof raw === "string") {
    try {
      arr = JSON.parse(raw);
    } catch {
      return [];
    }
  }
  if (!Array.isArray(arr)) return [];
  return arr
    .filter((d): d is Record<string, unknown> => !!d && typeof d === "object")
    .map((d) => ({
      name: String(d.name ?? "").trim(),
      price: Number(d.price),
      emoji: String(d.emoji ?? "🍸"),
    }))
    .filter((d) => d.name.length > 0 && Number.isFinite(d.price) && d.price > 0);
}

function nullableBool(v: unknown): boolean | null {
  return typeof v === "boolean" ? v : null;
}

function drinksSource(fs: OwnerVenueRow["field_sources"]): { url: string | null; date: string | null } | null {
  const p = fs?.popular_drinks;
  if (!p) return null;
  const url = typeof p.url === "string" ? p.url : null;
  const date = typeof p.date === "string" ? p.date : typeof p.at === "string" ? p.at : null;
  return url || date ? { url, date } : null;
}

export interface OwnerVenueDto {
  id: string;
  slug: string;
  name: string;
  type: string;
  city: string | null;
  neighborhood: string | null;
  address: string | null;
  phone: string | null;
  website: string | null;
  instagramHandle: string | null;
  imageUrl: string | null;
  agePolicy: string | null;
  priceTier: number | null;
  avgSpend: number | null;
  coverMen: number | null;
  coverWomen: number | null;
  openTime: string | null;
  closeTime: string | null;
  happyHourUntil: string | null;
  dressCode: string | null;
  parking: string | null;
  timezone: string | null;
  musicGenres: string[];
  vibes: string[];
  hours: OwnerDayHours[] | null;
  drinks: OwnerDrink[];
  drinksSource: { url: string | null; date: string | null } | null;
  amenities: OwnerAmenities;
  googleSyncedAt: string | null;
  visibility: ListingVisibility;
}

export function toOwnerVenueDto(row: OwnerVenueRow): OwnerVenueDto {
  return {
    id: row.id,
    slug: row.slug,
    name: row.name,
    type: row.type,
    city: row.city ?? null,
    neighborhood: row.neighborhood ?? null,
    address: row.address ?? null,
    phone: row.phone ?? null,
    website: row.website ?? null,
    instagramHandle: row.instagram_handle ?? null,
    imageUrl: row.image_url ?? null,
    agePolicy: row.age_policy ?? null,
    priceTier: row.price_tier ?? null,
    // 0 in this dataset means "no data", not "free" — it showed as a confident
    // "$0" on 1,665 venues before this rule existed.
    avgSpend: row.avg_spend ? row.avg_spend : null,
    coverMen: row.cover_men ?? null,
    coverWomen: row.cover_women ?? null,
    openTime: row.open_time ?? null,
    closeTime: row.close_time ?? null,
    happyHourUntil: row.happy_hour_until ?? null,
    dressCode: row.dress_code || null,
    parking: row.parking || null,
    timezone: row.timezone ?? null,
    musicGenres: row.music_genres ?? [],
    vibes: row.vibes ?? [],
    hours: toWeeklyHours(row.hours),
    drinks: parseOwnerDrinks(row.popular_drinks),
    drinksSource: drinksSource(row.field_sources),
    amenities: {
      outdoorSeating: nullableBool(row.outdoor_seating),
      goodForGroups: nullableBool(row.good_for_groups),
      goodForWatchingSports: nullableBool(row.good_for_watching_sports),
      hasLiveMusic: nullableBool(row.has_live_music),
      reservable: nullableBool(row.reservable),
      restroom: nullableBool(row.restroom),
      servesVegetarianFood: nullableBool(row.serves_vegetarian_food),
      wheelchairAccessible: nullableBool(row.wheelchair_accessible),
    },
    googleSyncedAt: row.google_synced_at ?? null,
    visibility: listingVisibility(row),
  };
}
