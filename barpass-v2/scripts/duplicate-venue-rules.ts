/**
 * Pure grouping logic for duplicate venue detection. No network, no env — so it
 * can be tested (scripts/duplicate-venue-rules.test.ts) without touching prod.
 *
 * A duplicate is decided by EVIDENCE, never by a similar name:
 *
 *   place_id     two rows carrying the same google_place_id. Google issues one
 *                place id per business, so this is proof, not a heuristic.
 *   address+geo  same normalized street address AND coordinates within a few
 *                metres AND the same normalized name. Catches the case where a
 *                re-import wrote a fresh place id for the same bar.
 *   same-roof    same address + coordinates but DIFFERENT names. A hotel lobby
 *                bar and its rooftop club share an address and are two real,
 *                separate venues, so this is reported for a human to read and
 *                is never proposed for removal.
 *
 * Name equality alone is never a criterion: three Sonny's BBQ in Gainesville
 * are three real restaurants, and a name-only pass already wrongly excluded
 * three Miller's Ale House rows and Bloomington's Kilroy's.
 */

export interface VenueRow {
  id: string;
  name: string;
  slug: string;
  city: string | null;
  address: string | null;
  lat: number | null;
  lng: number | null;
  review_count: number | null;
  rating: number | null;
  google_place_id: string | null;
  excluded_reason: string | null;
  business_status: string | null;
  image_url: string | null;
  created_at: string | null;
  google_synced_at: string | null;
}

export type Criterion = "place_id" | "address+geo" | "same-roof";

export interface DuplicateGroup {
  criterion: Criterion;
  /** Metres between the two furthest-apart rows, when coordinates exist. */
  spreadMeters: number | null;
  rows: VenueRow[];
}

/** Coordinates this close are the same front door, not two venues. */
export const GEO_TOLERANCE_METERS = 60;

const STREET_WORDS: Record<string, string> = {
  street: "st", str: "st", st: "st",
  avenue: "ave", av: "ave", ave: "ave",
  boulevard: "blvd", blvd: "blvd",
  road: "rd", rd: "rd",
  drive: "dr", dr: "dr",
  lane: "ln", ln: "ln",
  place: "pl", pl: "pl",
  court: "ct", ct: "ct",
  terrace: "ter", ter: "ter",
  highway: "hwy", hwy: "hwy",
  parkway: "pkwy", pkwy: "pkwy",
  circle: "cir", cir: "cir",
  square: "sq", sq: "sq",
  trail: "trl", trl: "trl",
  north: "n", south: "s", east: "e", west: "w",
  northeast: "ne", northwest: "nw", southeast: "se", southwest: "sw",
  suite: "ste", ste: "ste", unit: "ste", apt: "ste", "#": "ste",
};

/**
 * "1728 Southwest 2nd Avenue, Gainesville, FL 32601, USA" and
 * "1728 SW 2nd Ave, Gainesville, FL 32601" must collapse to the same key —
 * Google returns both spellings for the same door depending on when the row
 * was written. The trailing country and any punctuation go; the house number,
 * street and zip stay, because those are what make two addresses different.
 */
export function normalizeAddress(address: string | null): string {
  if (!address) return "";
  return address
    .toLowerCase()
    .replace(/,?\s*(usa|united states|us)\s*$/i, "")
    .replace(/[.,#]/g, " ")
    .split(/\s+/)
    .filter(Boolean)
    .map((w) => STREET_WORDS[w] ?? w)
    .join(" ")
    .trim();
}

/** Case/punctuation/&-tolerant name key. Used to GRADE a geo match, never to
 *  create one on its own. */
export function normalizeName(name: string | null): string {
  return (name ?? "")
    .toLowerCase()
    .replace(/&/g, "and")
    .replace(/[^a-z0-9]/g, "");
}

export function haversineMeters(
  a: { lat: number; lng: number },
  b: { lat: number; lng: number },
): number {
  const R = 6_371_000;
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const lat1 = toRad(a.lat);
  const lat2 = toRad(b.lat);
  const h =
    Math.sin(dLat / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(h)));
}

function spread(rows: VenueRow[]): number | null {
  const pts = rows.filter((r) => r.lat !== null && r.lng !== null) as (VenueRow & {
    lat: number;
    lng: number;
  })[];
  if (pts.length < 2) return null;
  let max = 0;
  for (let i = 0; i < pts.length; i++) {
    for (let j = i + 1; j < pts.length; j++) {
      max = Math.max(max, haversineMeters(pts[i], pts[j]));
    }
  }
  return max;
}

function withinTolerance(rows: VenueRow[]): boolean {
  const s = spread(rows);
  // No coordinates on either row is not evidence of sameness; the address key
  // already matched, but without geometry we refuse to call it a duplicate.
  return s !== null && s <= GEO_TOLERANCE_METERS;
}

/**
 * Groups rows into duplicate sets. Every row lands in at most one group:
 * place_id wins, then address+geo over the leftovers.
 */
export function groupDuplicates(rows: VenueRow[]): DuplicateGroup[] {
  const groups: DuplicateGroup[] = [];
  const claimed = new Set<string>();

  const byPlaceId = new Map<string, VenueRow[]>();
  for (const r of rows) {
    const pid = (r.google_place_id ?? "").trim();
    if (!pid) continue;
    byPlaceId.set(pid, [...(byPlaceId.get(pid) ?? []), r]);
  }
  for (const set of byPlaceId.values()) {
    if (set.length < 2) continue;
    for (const r of set) claimed.add(r.id);
    groups.push({ criterion: "place_id", spreadMeters: spread(set), rows: sortRows(set) });
  }

  const byAddress = new Map<string, VenueRow[]>();
  for (const r of rows) {
    if (claimed.has(r.id)) continue;
    const key = normalizeAddress(r.address);
    if (!key) continue;
    byAddress.set(key, [...(byAddress.get(key) ?? []), r]);
  }
  for (const set of byAddress.values()) {
    if (set.length < 2) continue;
    if (!withinTolerance(set)) continue;

    // One address can hold BOTH cases at once: Ann Arbor's 300 S Main St has
    // "Echelon Kitchen and Bar" twice AND a second, real venue ("Hunã") in the
    // same building. Judging the bucket as a whole would have buried that
    // duplicate inside a same-roof group nobody acts on, so split by name
    // first: repeated names are duplicates, the leftovers share a roof.
    const byName = new Map<string, VenueRow[]>();
    for (const r of set) {
      const key = normalizeName(r.name);
      byName.set(key, [...(byName.get(key) ?? []), r]);
    }
    const leftovers: VenueRow[] = [];
    for (const named of byName.values()) {
      if (named.length < 2) {
        leftovers.push(...named);
        continue;
      }
      groups.push({ criterion: "address+geo", spreadMeters: spread(named), rows: sortRows(named) });
    }
    if (leftovers.length > 1) {
      groups.push({ criterion: "same-roof", spreadMeters: spread(leftovers), rows: sortRows(leftovers) });
    }
  }

  return groups;
}

/** Rows ordered survivor-first. */
function sortRows(rows: VenueRow[]): VenueRow[] {
  return [...rows].sort(compareSurvivor);
}

const richness = (r: VenueRow) =>
  (r.image_url ? 1 : 0) + (r.google_place_id ? 1 : 0) + (r.business_status ? 1 : 0);

/**
 * Who survives. Order matters and each step is a fact, not a preference:
 *  1. a row already excluded has already lost;
 *  2. a permanently-closed listing loses to a live one;
 *  3. more reviews = the listing people actually use (same rule as the
 *     existing address dedupe, kept so both scripts agree);
 *  4. more filled columns;
 *  5. older created_at — the id other tables are most likely to point at.
 */
export function compareSurvivor(a: VenueRow, b: VenueRow): number {
  const alive = (r: VenueRow) =>
    (r.excluded_reason ? 0 : 1) + (r.business_status === "CLOSED_PERMANENTLY" ? 0 : 1);
  if (alive(a) !== alive(b)) return alive(b) - alive(a);
  if ((a.review_count ?? 0) !== (b.review_count ?? 0)) {
    return (b.review_count ?? 0) - (a.review_count ?? 0);
  }
  if (richness(a) !== richness(b)) return richness(b) - richness(a);
  return (a.created_at ?? "").localeCompare(b.created_at ?? "");
}

/** Groups whose rows are ALL already excluded need no action. */
export function isResolved(group: DuplicateGroup): boolean {
  return group.rows.filter((r) => !r.excluded_reason).length < 2;
}
