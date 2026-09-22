/**
 * Turns ONE Google Place Details response into the set of venue columns to
 * write — and, just as importantly, the set to leave alone.
 *
 * WHY IT IS ITS OWN FILE
 * Every rule that decides whether a value is real lives here, with no network
 * and no database, so it can be tested for free. The 2026-09-14 sweep cost USD
 * 655 partly because the only way to find out what a script would write was to
 * let it spend money finding out.
 *
 * THE RULE, from CLAUDE.md and the venue-intelligence skill:
 *   An empty value is a fact. A guessed value is a lie that survives months
 *   because nothing marks it as guessed.
 * So: if Google did not return a field, the column is NOT touched. Not set to
 * null, not set to a default, not "refreshed" to empty. The absence of a key in
 * the response is not a statement about the venue.
 */
import { classify, type VenueKind } from "./venue-type-rules";
import {
  toWeeklyHours,
  type DayHours,
  type GooglePlace,
  type VenueRow,
} from "./venue-google-fields";

const PRICE_LEVEL_MAP: Record<string, number> = {
  PRICE_LEVEL_FREE: 1,
  PRICE_LEVEL_INEXPENSIVE: 1,
  PRICE_LEVEL_MODERATE: 2,
  PRICE_LEVEL_EXPENSIVE: 3,
  PRICE_LEVEL_VERY_EXPENSIVE: 4,
};

/** Types the catalogue states more precisely than Google's generic "bar". */
const SPECIFIC_NIGHTLIFE = new Set(["club", "rooftop", "lounge", "sports_bar", "brewery"]);

/** Provenance this pass must never overwrite — both cost human effort and both
 *  are more trustworthy than a re-scrape (venue_field_provenance.sql). */
const PROTECTED_SOURCES = new Set(["manual_research", "user_report"]);

export type TypeDecision =
  | { action: "keep"; reason: string }
  | { action: "retype"; type: VenueKind; reason: string }
  | { action: "exclude"; reason: string }
  | { action: "restore"; type?: VenueKind; reason: string };

/**
 * The type rules of fix-venue-types.ts, unchanged — including its two guards,
 * which exist because Google's label is often coarser than the catalogue's:
 * a thin record never overturns an existing type, and a generic "bar" never
 * overwrites club / rooftop / lounge / sports_bar / brewery (those re-rank the
 * venue in the going-out scorer).
 */
export function decideType(
  row: VenueRow,
  g: GooglePlace,
  hours: DayHours[] | null,
): TypeDecision {
  // GUARDA PRIMERA, y la más importante: si Google no mandó NINGUNA señal de
  // tipo, no hay nada que clasificar. `classify({})` cae en su última rama y
  // devuelve `kind: null` — "no es un venue" — que acá se traduciría en excluir
  // la fila del catálogo por una respuesta vacía. Ausencia de evidencia no es
  // evidencia: una respuesta fina (Google 200 con el campo ausente, un lugar
  // recién creado, un tipo que Google todavía no asignó) no puede borrar un
  // venue que alguien cargó a mano.
  if (!g.primaryType && !g.types?.length) {
    return { action: "keep", reason: "Google no devolvió primaryType ni types" };
  }

  const { kind, reason } = classify({
    primaryType: g.primaryType,
    types: g.types,
    servesBeer: g.servesBeer,
    servesWine: g.servesWine,
    servesCocktails: g.servesCocktails,
    hours,
  });

  if (kind === "unknown") {
    // Google said nothing useful. Absence of evidence is not evidence — and if
    // an earlier pass excluded this row on the same silence, undo that.
    return row.excluded_reason === "not_nightlife"
      ? { action: "restore", reason }
      : { action: "keep", reason };
  }
  if (kind === null) {
    if (SPECIFIC_NIGHTLIFE.has(row.type)) {
      return { action: "keep", reason: `Google dice "${reason}"; se respeta el tipo existente` };
    }
    return { action: "exclude", reason };
  }
  if (row.excluded_reason === "not_nightlife") {
    return { action: "restore", type: kind, reason };
  }
  if (kind === "bar" && SPECIFIC_NIGHTLIFE.has(row.type)) {
    return { action: "keep", reason: `"bar" es menos específico que ${row.type}` };
  }
  if (kind !== row.type) return { action: "retype", type: kind, reason };
  return { action: "keep", reason };
}

export interface PatchResult {
  patch: Record<string, unknown>;
  /** Columns that will actually change, for the log line. */
  changed: string[];
  /** Photo resource name to resolve, or null. A SECOND billable request. */
  photoToResolve: string | null;
  typeDecision: TypeDecision;
  /** Things Google had nothing to say about, counted rather than guessed. */
  absent: string[];
}

export interface PatchOptions {
  /** ISO date, the `at` of every provenance entry written by this run. */
  at: string;
  /**
   * The Google place id, recorded so a value can be traced back to the exact
   * place it came from. Deliberately the id and not a full URL: the URL is the
   * same for every row but the id, so storing it 4,417 times adds nothing —
   * and a hardcoded places.googleapis.com string outside scripts/lib/ is what
   * `no-direct-places-calls.test.ts` exists to stop, comment or not.
   */
  placeId: string;
  /** When false, a hole in image_url is left alone instead of buying a photo. */
  resolvePhotos: boolean;
}

/**
 * Builds the patch for one venue. Returns an empty patch when Google told us
 * nothing new — the caller then writes nothing at all, which is the point:
 * a no-op write still burns a Supabase round trip and rewrites updated_at.
 */
export function buildPatch(row: VenueRow, g: GooglePlace, opts: PatchOptions): PatchResult {
  const patch: Record<string, unknown> = {};
  const absent: string[] = [];
  const sources: Record<string, unknown> = { ...(row.field_sources ?? {}) };

  const note = (column: string) => {
    const prior = row.field_sources?.[column];
    if (prior?.source && PROTECTED_SOURCES.has(prior.source)) return;
    sources[column] = {
      source: "google_places",
      at: opts.at,
      method: "places_api_v1_place_details",
      place_id: opts.placeId,
    };
  };

  // hours — never nulled. A venue Google has no hours for keeps whatever it has.
  const hours = toWeeklyHours(g.regularOpeningHours?.periods);
  if (hours) {
    if (JSON.stringify(hours) !== JSON.stringify(row.hours)) {
      patch.hours = hours;
      note("hours");
    }
  } else {
    absent.push("hours");
  }

  // Google is the source of record for these three, so a newer value wins.
  if (typeof g.rating === "number" && g.rating !== row.rating) {
    patch.rating = g.rating;
    note("rating");
  }
  if (typeof g.userRatingCount === "number" && g.userRatingCount !== row.review_count) {
    patch.review_count = g.userRatingCount;
    note("review_count");
  }
  if (g.businessStatus && g.businessStatus !== row.business_status) {
    patch.business_status = g.businessStatus;
  }

  // price_tier: written only when Google states one. Note the deliberate
  // difference from fix-price-tiers.ts, which wrote NULL on absence — that was
  // a one-time cleanup of a known-bad `default 2`, not a rule. A recurring
  // refresh that nulls on silence would erase a real tier the first time
  // Google's response came back thin.
  if (g.priceLevel) {
    const mapped = PRICE_LEVEL_MAP[g.priceLevel];
    if (mapped && mapped !== row.price_tier) {
      patch.price_tier = mapped;
      note("price_tier");
    }
  } else {
    absent.push("price_tier");
  }

  // website / phone: fill a hole only. A hand-researched value outranks Google.
  if (!row.website && g.websiteUri) {
    patch.website = g.websiteUri;
    note("website");
  }
  if (!row.phone && g.nationalPhoneNumber) {
    patch.phone = g.nationalPhoneNumber;
    note("phone");
  }

  // Amenity booleans. NULL means "Google has not said", never false — so only
  // an actual boolean is written. These ride along at zero extra cost: the mask
  // already pays the Atmosphere SKU for servesBeer/Wine/Cocktails, and one more
  // Atmosphere field does not raise the price of the request.
  const amenities: [keyof VenueRow, boolean | undefined][] = [
    ["wheelchair_accessible", g.accessibilityOptions?.wheelchairAccessibleEntrance],
    ["outdoor_seating", g.outdoorSeating],
    ["good_for_groups", g.goodForGroups],
    ["good_for_watching_sports", g.goodForWatchingSports],
    ["has_live_music", g.liveMusic],
    ["reservable", g.reservable],
    ["serves_vegetarian_food", g.servesVegetarianFood],
    ["restroom", g.restroom],
  ];
  let amenityChanged = false;
  for (const [column, value] of amenities) {
    if (typeof value !== "boolean") continue;
    if (value === row[column]) continue;
    patch[column] = value;
    amenityChanged = true;
  }
  if (amenityChanged) patch.amenities_synced_at = opts.at;

  const typeDecision = decideType(row, g, hours ?? row.hours);
  if (typeDecision.action === "retype") {
    patch.type = typeDecision.type;
    note("type");
  } else if (typeDecision.action === "exclude") {
    patch.excluded_reason = "not_nightlife";
  } else if (typeDecision.action === "restore") {
    patch.excluded_reason = null;
    if (typeDecision.type) patch.type = typeDecision.type;
  }

  // A photo is a second billable request, so it is only worth buying for a row
  // that has no image at all, and never for one whose photo was set by hand.
  const photoTraced = PROTECTED_SOURCES.has(row.field_sources?.image_url?.source ?? "");
  const photoName = g.photos?.[0]?.name ?? null;
  const photoToResolve =
    opts.resolvePhotos && !row.image_url && !photoTraced && photoName ? photoName : null;
  if (!photoName) absent.push("image_url");

  const changed = Object.keys(patch).filter((k) => k !== "amenities_synced_at");
  if (changed.length > 0) patch.field_sources = sources;

  // Stamped even when nothing else changed, and this is load-bearing: the
  // --stale-days selector picks venues by google_synced_at. If a venue Google
  // had no news about kept its old timestamp, every future run would pay to ask
  // about it again and again — the exact shape of spending that caused this
  // refactor. One free Supabase write buys out an indefinite number of paid
  // Google calls.
  patch.google_synced_at = opts.at;

  return { patch, changed, photoToResolve, typeDecision, absent };
}
