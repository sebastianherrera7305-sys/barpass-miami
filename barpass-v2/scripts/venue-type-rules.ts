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
  "karaoke", "live_music_venue", "concert_hall", "comedy_club", "lounge", "hookah_bar",
]);

/** Primary types that are restaurants first. They can stay in the catalogue —
 *  people do drink at them — but they are not where the night is, and the
 *  going-out scorer already ranks `restaurant` at zero. */
const RESTAURANT_PRIMARY = /(_restaurant|steak_house|bistro|diner|cafe|cafeteria|food_court|deli|bakery|breakfast|brunch|fast_food|pizza|sandwich|sushi|ramen|barbecue|seafood|buffet)/;

/** Primary types that are STRONG evidence a place is not a venue. A shop is a
 *  shop; no amount of missing data changes that. */
const NOT_NIGHTLIFE = new Set([
  "store", "liquor_store", "grocery_store", "convenience_store", "farm",
  "indoor_golf_course", "golf_course", "movie_theater",
  "gym", "spa", "hotel", "lodging", "corporate_office", "park", "stadium",
]);

/** Primary types that say almost nothing either way. Google files real
 *  warehouse clubs as "event_venue" — Factory Town in Miami has primaryType
 *  event_venue, no opening hours and no alcohol flags at all, and an earlier
 *  version of this file excluded it on that basis. It is a club the owner has
 *  personally been to and that this app has built features for.
 *
 *  Absence of evidence is not evidence. A thin Google record must never
 *  overturn a type the catalogue already holds — the same rule as everywhere
 *  else here: an empty value is a fact, not a licence to guess. */
const AMBIGUOUS = new Set([
  "event_venue", "banquet_hall", "wedding_venue", "point_of_interest",
  "establishment", "tourist_attraction", "amusement_center", "bowling_alley",
  "performing_arts_theater", "service", "market",
]);

export interface TypeSignals {
  primaryType?: string;
  types?: string[];
  servesBeer?: boolean;
  servesWine?: boolean;
  servesCocktails?: boolean;
  /** The venue's real weekly schedule, if we have it. */
  hours?: { day: number; open: string; close: string }[] | null;
}

/** Nights per week this venue is still open after midnight. A close time
 *  between 00:00 and 08:00 belongs to the previous night. */
export function lateNights(hours: TypeSignals["hours"]): number {
  if (!hours?.length) return 0;
  return hours.filter((h) => {
    const hh = Number(h.close.split(":")[0]);
    return Number.isFinite(hh) && hh >= 0 && hh < 8;
  }).length;
}

export type VenueKind = "club" | "bar" | "lounge" | "sports_bar" | "rooftop" | "brewery" | "restaurant";

export interface Classification {
  /** null = positively not a venue. "unknown" = Google says nothing useful;
   *  the caller must keep whatever the catalogue already holds. */
  kind: VenueKind | "unknown" | null;
  /** Why, for provenance and for the report. */
  reason: string;
}

export function classify(s: TypeSignals): Classification {
  const primary = s.primaryType ?? s.types?.[0] ?? "";
  const all = new Set(s.types ?? []);
  const pours = Boolean(s.servesCocktails || s.servesBeer || s.servesWine);

  // Keep the finer distinctions the app actually ranks on: the going-out
  // scorer weights club 18, bar 15, lounge and rooftop 10, brewery and sports
  // bar 6. Collapsing everything to "bar" would silently re-rank the catalogue.
  if (primary === "night_club" || primary === "dance_hall") return { kind: "club", reason: `primary=${primary}` };
  if (primary === "brewery" || primary === "brewpub" || primary === "beer_hall" || primary === "beer_garden") {
    return { kind: "brewery", reason: `primary=${primary}` };
  }
  if (primary === "sports_bar") return { kind: "sports_bar", reason: `primary=${primary}` };
  if (primary === "lounge" || primary === "hookah_bar") return { kind: "lounge", reason: `primary=${primary}` };
  if (NIGHTLIFE_PRIMARY.has(primary)) return { kind: "bar", reason: `primary=${primary}` };

  if (RESTAURANT_PRIMARY.test(primary) || primary === "restaurant") {
    // …unless it actually behaves like a bar. Google files Miller's Ale House
    // and The TOP as `american_restaurant`; both pour drinks and both are open
    // until 2am, and both are where UF students actually go. Calling them
    // restaurants drops them out of the going-out feed entirely, because
    // VenueRanking scores `restaurant` at zero — the opposite of what the
    // college market needs. Sonny's BBQ closes at 9pm and stays a restaurant,
    // so this separates the two cleanly.
    if (pours && lateNights(s.hours) >= 1) {
      return { kind: "bar", reason: `primary=${primary} but open past midnight and serves alcohol` };
    }
    return { kind: "restaurant", reason: `primary=${primary}` };
  }

  if (AMBIGUOUS.has(primary)) {
    // Decide on behaviour if we have any, otherwise hand the decision back to
    // the caller (which keeps whatever the row already says).
    if (all.has("night_club")) return { kind: "club", reason: `types include night_club (primary=${primary})` };
    if (pours && lateNights(s.hours) >= 1) {
      return { kind: "bar", reason: `primary=${primary} but open past midnight and serves alcohol` };
    }
    if (all.has("bar")) return { kind: "bar", reason: `types include bar (primary=${primary})` };
    return { kind: "unknown", reason: `primary=${primary} tells us nothing; keeping what we have` };
  }

  if (NOT_NIGHTLIFE.has(primary)) {
    // Escape hatches, both earned by behaviour rather than by label.
    // A warehouse Google files as "event_venue" that is also listed as a night
    // club and pours drinks is a club.
    if (all.has("night_club") && pours) return { kind: "club", reason: `primary=${primary} but night_club + serves alcohol` };
    // And anything that pours drinks and is open past midnight is somewhere
    // people go out — AREA15 in Las Vegas is filed as a tourist_attraction,
    // Lucky Strike as a bowling_alley, and a concert hall as a concert_hall.
    // The same test that rescued the college bars applies here.
    if (pours && lateNights(s.hours) >= 1) {
      return { kind: "bar", reason: `primary=${primary} but open past midnight and serves alcohol` };
    }
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
