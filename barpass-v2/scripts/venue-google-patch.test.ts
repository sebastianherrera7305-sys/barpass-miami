import { describe, expect, it } from "vitest";
import { buildPatch, decideType } from "./venue-google-patch";
import {
  REFRESH_FIELD_MASK,
  toWeeklyHours,
  type GooglePlace,
  type VenueRow,
} from "./venue-google-fields";
import { estimateSweep, rootField } from "./lib/places-pricing";

const OPTS = { at: "2026-09-22T00:00:00.000Z", placeId: "p1", resolvePhotos: true };

function row(over: Partial<VenueRow> = {}): VenueRow {
  return {
    id: "v1", name: "Rush", city: "Gainesville", type: "bar",
    google_place_id: "p1", hours: null, rating: null, review_count: null,
    price_tier: null, image_url: null, website: null, phone: null,
    business_status: null, excluded_reason: null, field_sources: null,
    wheelchair_accessible: null, outdoor_seating: null, good_for_groups: null,
    good_for_watching_sports: null, has_live_music: null, reservable: null,
    serves_vegetarian_food: null, restroom: null,
    ...over,
  };
}

describe("toWeeklyHours", () => {
  it("keeps every period, not just the first — the bug that showed Tuesday hours on a Friday venue", () => {
    const hours = toWeeklyHours([
      { open: { day: 5, hour: 20, minute: 0 }, close: { day: 6, hour: 2, minute: 0 } },
      { open: { day: 6, hour: 21, minute: 0 }, close: { day: 0, hour: 2, minute: 0 } },
    ]);
    expect(hours).toEqual([
      { day: 5, open: "20:00", close: "02:00" },
      { day: 6, open: "21:00", close: "02:00" },
    ]);
  });

  it("returns null for no periods — never an invented schedule", () => {
    expect(toWeeklyHours(undefined)).toBeNull();
    expect(toWeeklyHours([])).toBeNull();
  });
});

describe("buildPatch — an empty value is a fact, a guessed one is a lie", () => {
  it("touches nothing but the sync stamp when Google returns an empty record", () => {
    const r = row({ hours: [{ day: 5, open: "20:00", close: "02:00" }], price_tier: 3, rating: 4.5 });
    const { patch, changed } = buildPatch(r, {}, OPTS);
    expect(changed).toEqual([]);
    // Crucially: hours and price_tier are NOT nulled just because Google was silent.
    expect(patch).not.toHaveProperty("hours");
    expect(patch).not.toHaveProperty("price_tier");
    expect(Object.keys(patch)).toEqual(["google_synced_at"]);
  });

  it("always stamps google_synced_at, so --stale-days cannot re-buy the same silence forever", () => {
    const { patch } = buildPatch(row(), {}, OPTS);
    expect(patch.google_synced_at).toBe(OPTS.at);
  });

  it("leaves price_tier alone when Google states none, instead of nulling it", () => {
    // Deliberate divergence from fix-price-tiers.ts, whose NULL-on-absence was a
    // one-time cleanup of a bad `default 2`, not a rule for a recurring refresh.
    const { patch, absent } = buildPatch(row({ price_tier: 3 }), { rating: 4.1 }, OPTS);
    expect(patch).not.toHaveProperty("price_tier");
    expect(absent).toContain("price_tier");
  });

  it("writes an amenity only when Google sent a real boolean — NULL never becomes false", () => {
    const { patch } = buildPatch(row(), { restroom: true, goodForGroups: undefined }, OPTS);
    expect(patch.restroom).toBe(true);
    expect(patch).not.toHaveProperty("good_for_groups");
  });

  it("fills a hole in website/phone but never overwrites one we already have", () => {
    const r = row({ website: "https://researched.example", phone: null });
    const { patch } = buildPatch(r, { websiteUri: "https://google.example", nationalPhoneNumber: "(352) 555-0100" }, OPTS);
    expect(patch).not.toHaveProperty("website");
    expect(patch.phone).toBe("(352) 555-0100");
  });

  it("never replaces a manual_research provenance entry", () => {
    const r = row({ field_sources: { rating: { source: "manual_research" } }, rating: 4.0 });
    const { patch } = buildPatch(r, { rating: 4.4 }, OPTS);
    const sources = patch.field_sources as Record<string, { source: string }>;
    expect(patch.rating).toBe(4.4); // the value still refreshes — Google owns ratings
    expect(sources.rating.source).toBe("manual_research"); // but the claim of origin does not
  });

  it("does not buy a photo for a venue that already has one", () => {
    expect(buildPatch(row({ image_url: "https://lh3/x" }), { photos: [{ name: "places/p1/photos/a" }] }, OPTS).photoToResolve).toBeNull();
    expect(buildPatch(row(), { photos: [{ name: "places/p1/photos/a" }] }, OPTS).photoToResolve).toBe("places/p1/photos/a");
  });

  it("does not buy a photo for a venue whose photo was set by hand", () => {
    const r = row({ field_sources: { image_url: { source: "manual_research" } } });
    expect(buildPatch(r, { photos: [{ name: "places/p1/photos/a" }] }, OPTS).photoToResolve).toBeNull();
  });

  it("skips photo resolution entirely under --no-photos", () => {
    const res = buildPatch(row(), { photos: [{ name: "places/p1/photos/a" }] }, { ...OPTS, resolvePhotos: false });
    expect(res.photoToResolve).toBeNull();
  });
});

describe("decideType — a thin Google record never overturns the catalogue", () => {
  const late = [{ day: 5, open: "21:00", close: "02:00" }];

  it("keeps the existing type when Google says nothing useful", () => {
    expect(decideType(row({ type: "club" }), { primaryType: "event_venue" }, null).action).toBe("keep");
  });

  it("does not downgrade a club to a generic bar", () => {
    const g: GooglePlace = { primaryType: "bar", servesCocktails: true };
    expect(decideType(row({ type: "club" }), g, late).action).toBe("keep");
  });

  it("rescues a late-closing college bar Google files as a restaurant", () => {
    // Miller's Ale House / The TOP: `american_restaurant`, pours, open past
    // midnight. Typed `restaurant` they score zero in the going-out feed.
    const g: GooglePlace = { primaryType: "american_restaurant", servesBeer: true };
    const d = decideType(row({ type: "restaurant" }), g, late);
    expect(d).toMatchObject({ action: "retype", type: "bar" });
  });

  it("never excludes a venue on an empty response — absence of evidence is not evidence", () => {
    // classify({}) falls through to its last branch and answers "not nightlife".
    // Acted on literally, one thin Google response would drop a hand-entered
    // venue out of the catalogue. It must be a no-op instead.
    expect(decideType(row({ type: "bar" }), {}, null).action).toBe("keep");
    expect(buildPatch(row({ type: "bar" }), {}, OPTS).patch).not.toHaveProperty("excluded_reason");
  });

  it("undoes an exclusion once the venue classifies as nightlife again", () => {
    const r = row({ type: "bar", excluded_reason: "not_nightlife" });
    const d = decideType(r, { primaryType: "night_club" }, late);
    expect(d).toMatchObject({ action: "restore", type: "club" });
  });
});

/**
 * THE REGRESSION THIS WHOLE FILE EXISTS FOR.
 *
 * Google bills one request at the dearest SKU its mask touches. Five narrow
 * passes pay five SKUs for the same venue; one wide pass pays one. If this ever
 * stops holding, the consolidation has been undone and somebody is about to get
 * another surprise on a card statement.
 */
describe("one pass vs the five it replaces", () => {
  const FIVE_PASSES: Record<string, string[]> = {
    "backfill-venue-hours": ["regularOpeningHours.periods"],
    "fix-venue-types": ["primaryType", "types", "servesBeer", "servesWine", "servesCocktails"],
    "fix-price-tiers": ["id", "priceLevel"],
    "fix-venue-photos": ["photos"],
    "refresh-venue-core-data": [
      "id", "displayName", "businessStatus", "rating", "userRatingCount",
      "websiteUri", "nationalPhoneNumber", "regularOpeningHours.periods", "photos.name",
    ],
  };

  it("asks for everything the five asked for", () => {
    // Compared on the ROOT field: the consolidated mask narrows `photos` to
    // `photos.name`, which returns the same resource name for the same price.
    const covered = new Set(REFRESH_FIELD_MASK.map(rootField));
    for (const mask of Object.values(FIVE_PASSES)) {
      for (const field of mask) expect(covered).toContain(rootField(field));
    }
  });

  it("costs strictly less than the five, for the 2,510 venues of 2026-09-14", () => {
    const venues = 2510;
    const five = Object.values(FIVE_PASSES).reduce(
      (sum, mask) => sum + estimateSweep("details", mask, venues).usd,
      0,
    );
    const one = estimateSweep("details", REFRESH_FIELD_MASK, venues).usd;
    expect(one).toBeLessThan(five);
    expect(one).toBeLessThan(five / 3);
  });

  it("carries the amenity fields for free, because the mask already pays Atmosphere", () => {
    const withoutAmenities = REFRESH_FIELD_MASK.filter(
      (f) => !["restroom", "goodForGroups", "outdoorSeating", "liveMusic", "reservable",
        "servesVegetarianFood", "goodForWatchingSports", "accessibilityOptions"].includes(f),
    );
    expect(estimateSweep("details", REFRESH_FIELD_MASK, 1000).usd).toBe(
      estimateSweep("details", withoutAmenities, 1000).usd,
    );
  });
});
