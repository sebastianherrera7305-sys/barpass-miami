/**
 * Places API (New) — what a request costs, worked out BEFORE it leaves.
 *
 * WHY THIS FILE EXISTS
 * On 2026-09-14 a sweep of 2,510 venues cost USD 655 in one day and the founder
 * found out from the card statement. Eleven scripts each opened their own fetch
 * to places.googleapis.com with its own narrow field mask, so the same venue was
 * paid for once per script. Nothing in the codebase could answer "what will this
 * run cost?" before running it. This table is that answer; places-client.ts
 * refuses to spend without consulting it.
 *
 * ###########################################################################
 * # THESE ARE LIST PRICES. VERIFY BEFORE TRUSTING ANY NUMBER THIS PRINTS.   #
 * # Source: https://developers.google.com/maps/billing-and-pricing/pricing  #
 * # Read on: 2026-09-22. First volume band only (0-100,000 calls/month).    #
 * # Everything downstream is an ESTIMATE, never an invoice.                 #
 * ###########################################################################
 *
 * THE BILLING RULE — and a correction to what we believed on 2026-09-14
 * We assumed a request paid every tier its field mask touched, once each. It
 * does not. Google bills a request once, at the "highest SKU applicable to your
 * request" (usage-and-billing, Places API New). A mask spanning Essentials and
 * Pro is billed Pro, full stop.
 *
 * The practical consequence runs the opposite way from the intuition: once you
 * are already paying for one Atmosphere field, every other field at or below
 * Atmosphere is free. Asking for MORE in one call is not more expensive. Five
 * narrow sweeps pay five SKUs; one wide call pays one. That is the whole fix.
 *
 * WHAT THIS MODULE DELIBERATELY DOES NOT MODEL, so the estimate stays honest:
 *  - Volume discounts above 100k/month. We use the dearest band, so a real bill
 *    can only come in under the estimate, never over it.
 *  - Any free monthly allotment Google grants per SKU. Same direction: the
 *    estimate is high early in a billing month.
 *  - Taxes, and any negotiated rate on this account.
 */

/** Google's SKU ladder for Places, cheapest to dearest. Index = how dear. */
export type SkuTier = "idsOnly" | "essentials" | "pro" | "enterprise" | "atmosphere";

export const TIER_ORDER: readonly SkuTier[] = [
  "idsOnly",
  "essentials",
  "pro",
  "enterprise",
  "atmosphere",
];

/** Place Photos has no field mask and one flat rate, so it sits off the ladder. */
export type BilledTier = SkuTier | "flat";

export type PlacesEndpoint = "details" | "textSearch" | "nearbySearch" | "photo";

export const PRICING_SOURCE =
  "https://developers.google.com/maps/billing-and-pricing/pricing";
export const PRICING_READ_ON = "2026-09-22";

/**
 * USD per 1,000 requests, first volume band. See the banner above before
 * believing any of it.
 *
 * Two entries are guesses in the SAFE direction, marked because a guess that
 * looks like a fact is how the music_genres mess happened:
 *  - textSearch.essentials: the published table lists Text Search IDs-Only
 *    (free) and Text Search Pro, with no separate Essentials row. Billed here
 *    at the Pro rate, i.e. over-estimated. VERIFY.
 *  - nearbySearch.idsOnly: no free IDs-Only row was published for Nearby
 *    Search the way there is for Text Search. Billed at the Pro rate. VERIFY.
 */
export const USD_PER_1000: Record<PlacesEndpoint, Record<SkuTier, number>> = {
  details: { idsOnly: 0, essentials: 5, pro: 17, enterprise: 20, atmosphere: 25 },
  textSearch: { idsOnly: 0, essentials: 32, pro: 32, enterprise: 35, atmosphere: 40 },
  nearbySearch: { idsOnly: 32, essentials: 32, pro: 32, enterprise: 35, atmosphere: 40 },
  // Place Details Photos: $7.00/1k. The tier keys are ignored for this endpoint.
  photo: { idsOnly: 7, essentials: 7, pro: 7, enterprise: 7, atmosphere: 7 },
};

export const USD_PER_1000_PHOTO = USD_PER_1000.photo.idsOnly;

/**
 * Field -> SKU tier, from Place Data Fields (New), read 2026-09-22.
 * The published table is cumulative ("all Pro fields, plus..."); listed here
 * is each field's OWN tier, which is what the max-tier rule needs.
 */
const FIELDS_BY_TIER: Record<SkuTier, readonly string[]> = {
  // `photos` is in IDs-Only, i.e. FREE. Asking for the photo LIST costs nothing;
  // downloading the photo BYTES is the separate photo SKU. fix-venue-photos.ts
  // asks only for `photos` and was never the expensive script — its media
  // fetches were. Worth knowing before "optimising" the wrong file.
  idsOnly: ["name", "id", "attributions", "consumerAlert", "movedPlace", "movedPlaceId", "photos"],
  essentials: ["addressComponents", "addressDescriptor", "adrFormatAddress", "formattedAddress",
    "location", "plusCode", "postalAddress", "shortFormattedAddress", "types", "viewport"],
  pro: ["businessStatus", "containingPlaces", "displayName", "entrances", "googleMapsLinks",
    "googleMapsTypeLabel", "googleMapsUri", "iconBackgroundColor", "iconMaskBaseUri",
    "navigationPoints", "openingDate", "primaryType", "primaryTypeDisplayName",
    "pureServiceAreaBusiness", "subDestinations", "timeZone", "utcOffsetMinutes"],
  // The dear ones the sweeps kept re-buying: priceLevel (fix-price-tiers),
  // regularOpeningHours (backfill-venue-hours, refresh-venue-core-data).
  enterprise: ["currentOpeningHours", "currentSecondaryOpeningHours", "internationalPhoneNumber",
    "nationalPhoneNumber", "priceLevel", "priceRange", "rating", "regularOpeningHours",
    "regularSecondaryOpeningHours", "transitStation", "userRatingCount", "websiteUri"],
  // And the dearest: servesBeer/Wine/Cocktails (fix-venue-types), editorialSummary.
  atmosphere: ["accessibilityOptions", "allowsDogs", "curbsidePickup", "delivery", "dineIn",
    "editorialSummary", "evChargeAmenitySummary", "evChargeOptions", "fuelOptions",
    "generativeSummary", "goodForChildren", "goodForGroups", "goodForWatchingSports",
    "liveMusic", "menuForChildren", "neighborhoodSummary", "outdoorSeating", "parkingOptions",
    "paymentOptions", "reservable", "restroom", "reviews", "reviewSummary", "routingSummaries",
    "servesBeer", "servesBreakfast", "servesBrunch", "servesCocktails", "servesCoffee",
    "servesDessert", "servesDinner", "servesLunch", "servesVegetarianFood", "servesWine",
    "takeout"],
};

const TIER_BY_FIELD: ReadonlyMap<string, SkuTier> = new Map(
  TIER_ORDER.flatMap((tier) => FIELDS_BY_TIER[tier].map((f) => [f, tier] as const)),
);

/**
 * A mask entry to the field that is actually billed.
 * "regularOpeningHours.periods" bills as regularOpeningHours; a Text Search
 * mask is prefixed "places." and that prefix is not a field.
 */
export function rootField(entry: string): string {
  const trimmed = entry.trim();
  const unprefixed = trimmed.startsWith("places.") ? trimmed.slice("places.".length) : trimmed;
  const dot = unprefixed.indexOf(".");
  return dot === -1 ? unprefixed : unprefixed.slice(0, dot);
}

export function normalizeMask(mask: string | readonly string[]): string[] {
  const parts = typeof mask === "string" ? mask.split(",") : [...mask];
  return parts.map(rootField).filter((f) => f.length > 0);
}

/** null means "we have never heard of this field" — the caller must not ignore it. */
export function tierOfField(field: string): SkuTier | null {
  return TIER_BY_FIELD.get(rootField(field)) ?? null;
}

export function dearerTier(a: SkuTier, b: SkuTier): SkuTier {
  return TIER_ORDER.indexOf(a) >= TIER_ORDER.indexOf(b) ? a : b;
}

export interface RequestCost {
  /** The single SKU this request is billed at. */
  tier: BilledTier;
  /** Estimated USD for one request at that SKU. */
  usd: number;
  /**
   * Fields absent from the table. They are billed at the DEAREST tier, because
   * an unknown field that silently costs nothing is exactly the failure this
   * module exists to prevent. Surface these; do not swallow them.
   */
  unknownFields: string[];
}

export function costOfRequest(
  endpoint: PlacesEndpoint,
  mask: string | readonly string[] = [],
): RequestCost {
  if (endpoint === "photo") {
    return { tier: "flat", usd: USD_PER_1000_PHOTO / 1000, unknownFields: [] };
  }

  const fields = normalizeMask(mask);
  const unknownFields: string[] = [];
  let tier: SkuTier = "idsOnly";

  for (const field of fields) {
    // "*" asks for everything, which includes the Atmosphere fields.
    if (field === "*") {
      tier = "atmosphere";
      continue;
    }
    const fieldTier = tierOfField(field);
    if (fieldTier === null) {
      unknownFields.push(field);
      tier = "atmosphere";
      continue;
    }
    tier = dearerTier(tier, fieldTier);
  }

  return { tier, usd: USD_PER_1000[endpoint][tier] / 1000, unknownFields };
}

export function usdFor(endpoint: PlacesEndpoint, tier: BilledTier, calls: number): number {
  const per1000 = tier === "flat" ? USD_PER_1000_PHOTO : USD_PER_1000[endpoint][tier];
  return (per1000 / 1000) * calls;
}

export function formatUsd(usd: number): string {
  return `$${usd.toFixed(2)}`;
}

/**
 * Price a whole sweep before anyone runs it — the "should we?" conversation
 * that did not happen on 2026-09-14. Pure math, no client, no network.
 */
export function estimateSweep(
  endpoint: PlacesEndpoint,
  mask: string | readonly string[],
  venues: number,
): { tier: BilledTier; usd: number } {
  const cost = costOfRequest(endpoint, mask);
  return { tier: cost.tier, usd: usdFor(endpoint, cost.tier, venues) };
}
