/**
 * What kind of venue is this, really?
 *
 * Gainesville, 2026-09-13: "nada de los bares de college, muy pocos". The
 * college bars were there — 9 of the 11 Google lists on the University Ave
 * strip. They were drowning. 54 of 84 Gainesville venues typed `bar` were not
 * bars: Olive Garden, Outback, LongHorn, three Sonny's BBQ, Applebee's, a
 * liquor store, a plant shop, an indoor golf course and a theatre.
 *
 * The cause: the old mapper asked "does the types array contain 'bar'?", and
 * every chain restaurant with a liquor licence does. Google also returns
 * `primaryType`, which is the place's actual identity, plus servesBeer /
 * servesWine / servesCocktails. Those answer the question honestly.
 */

/** Primary types that ARE nightlife. A gastropub and a karaoke room are places
 *  people go out to at night; that is the test, not whether they serve food. */
const NIGHTLIFE_PRIMARY = new Set([
  "night_club", "dance_hall",
  "bar", "pub", "cocktail_bar", "wine_bar", "sports_bar", "gastropub",
  "bar_and_grill", "beer_garden", "brewery", "brewpub", "beer_hall",
  "karaoke", "live_music_venue", "comedy_club", "lounge", "hookah_bar",
]);

/** Primary types that are restaurants first. They can stay in the catalogue —
 *  people do drink at them — but they are not where the night is, and the
 *  going-out scorer already ranks `restaurant` at zero. */
const RESTAURANT_PRIMARY = /(_restaurant|steak_house|bistro|diner|cafe|cafeteria|food_court|deli|bakery|breakfast|brunch|fast_food|pizza|sandwich|sushi|ramen|barbecue|seafood|buffet)/;

/** Primary types that do not belong in a nightlife app at all. */
const NOT_NIGHTLIFE = new Set([
  "store", "liquor_store", "grocery_store", "convenience_store", "farm",
  "indoor_golf_course", "golf_course", "performing_arts_theater", "movie_theater",
  "bowling_alley", "amusement_center", "gym", "spa", "hotel", "lodging",
  "event_venue", "banquet_hall", "wedding_venue", "corporate_office",
  "tourist_attraction", "park", "stadium",
]);

export interface TypeSignals {
  primaryType?: string;
  types?: string[];
  servesBeer?: boolean;
  servesWine?: boolean;
  servesCocktails?: boolean;
}

export type VenueKind = "club" | "bar" | "brewery" | "restaurant";

export interface Classification {
  /** null = does not belong in a nightlife catalogue. */
  kind: VenueKind | null;
  /** Why, for provenance and for the report. */
  reason: string;
}

export function classify(s: TypeSignals): Classification {
  const primary = s.primaryType ?? s.types?.[0] ?? "";
  const all = new Set(s.types ?? []);
  const pours = Boolean(s.servesCocktails || s.servesBeer || s.servesWine);

  if (primary === "night_club" || primary === "dance_hall") return { kind: "club", reason: `primary=${primary}` };
  if (primary === "brewery" || primary === "brewpub" || primary === "beer_hall") {
    return { kind: "brewery", reason: `primary=${primary}` };
  }
  if (NIGHTLIFE_PRIMARY.has(primary)) return { kind: "bar", reason: `primary=${primary}` };

  if (RESTAURANT_PRIMARY.test(primary) || primary === "restaurant") {
    return { kind: "restaurant", reason: `primary=${primary}` };
  }

  if (NOT_NIGHTLIFE.has(primary)) {
    // One escape hatch, and it has to be earned: a place Google files as
    // something else but that is listed as a night club AND actually pours
    // drinks is a venue (a warehouse "event_venue" that runs club nights).
    if (all.has("night_club") && pours) return { kind: "club", reason: `primary=${primary} but night_club + serves alcohol` };
    return { kind: null, reason: `primary=${primary} is not nightlife` };
  }

  // Unknown primary (coffee_shop, tea_house, sports_complex…). Decide on what
  // it actually does rather than on a label: a kava bar and a pool hall are
  // real college nightlife, a coffee shop that closes at 4pm is not. Hours are
  // checked by the caller; here, being listed as a bar is the signal.
  if (all.has("night_club")) return { kind: "club", reason: `types include night_club (primary=${primary})` };
  if (all.has("bar") && pours) return { kind: "bar", reason: `types include bar + serves alcohol (primary=${primary})` };
  if (all.has("bar")) return { kind: "bar", reason: `types include bar (primary=${primary})` };
  if (all.has("restaurant")) return { kind: "restaurant", reason: `types include restaurant (primary=${primary})` };
  return { kind: null, reason: `primary=${primary}, no bar or restaurant signal` };
}
