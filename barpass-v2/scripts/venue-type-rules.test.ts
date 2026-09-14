import { describe, it, expect } from "vitest";
import { classify } from "./venue-type-rules";

describe("classify", () => {
  it("keeps real nightlife as bar or club", () => {
    expect(classify({ primaryType: "night_club" }).kind).toBe("club");
    expect(classify({ primaryType: "cocktail_bar" }).kind).toBe("bar");
    expect(classify({ primaryType: "sports_bar" }).kind).toBe("sports_bar");
    expect(classify({ primaryType: "gastropub" }).kind).toBe("bar");
    expect(classify({ primaryType: "karaoke" }).kind).toBe("bar");
    expect(classify({ primaryType: "live_music_venue" }).kind).toBe("bar");
    expect(classify({ primaryType: "brewery" }).kind).toBe("brewery");
    expect(classify({ primaryType: "hookah_bar" }).kind).toBe("lounge");
    expect(classify({ primaryType: "beer_garden" }).kind).toBe("brewery");
  });

  it("demotes the chain restaurants that were filed as bars", () => {
    // Every one of these was type=bar in Gainesville on 2026-09-13.
    for (const p of ["italian_restaurant", "steak_house", "barbecue_restaurant",
                     "seafood_restaurant", "pizza_restaurant", "american_restaurant",
                     "chicken_wings_restaurant", "mexican_restaurant", "restaurant", "bistro"]) {
      expect(classify({ primaryType: p, types: ["bar", "restaurant"] }).kind).toBe("restaurant");
    }
  });

  it("keeps a late-night spot that serves drinks, whatever Google calls it", () => {
    // Miller's Ale House and The TOP: american_restaurant, open till 2am.
    const late = [{ day: 5, open: "11:00", close: "02:00" }];
    expect(classify({ primaryType: "american_restaurant", servesBeer: true, hours: late }).kind).toBe("bar");
    // Sonny's BBQ: same class of primary type, closes at 9pm. Still a restaurant.
    const early = [{ day: 5, open: "11:00", close: "21:00" }];
    expect(classify({ primaryType: "barbecue_restaurant", servesBeer: true, hours: early }).kind).toBe("restaurant");
    // Late but dry — a 24h diner is not nightlife.
    expect(classify({ primaryType: "diner", hours: late }).kind).toBe("restaurant");
  });

  it("rejects things that are not venues at all", () => {
    // Strong evidence only. A shop is a shop whatever else is missing.
    for (const p of ["liquor_store", "farm", "indoor_golf_course", "store", "movie_theater"]) {
      expect(classify({ primaryType: p, types: ["bar"] }).kind).toBeNull();
    }
  });

  it("lets a warehouse that actually runs club nights through", () => {
    expect(classify({ primaryType: "event_venue", types: ["night_club", "event_venue"], servesBeer: true }).kind).toBe("club");
  });

  it("never excludes on Google's silence — Factory Town", () => {
    // Factory Town, Miami: primaryType event_venue, no hours, no alcohol flags.
    // A real warehouse club. "unknown" means keep whatever the catalogue holds.
    expect(classify({ primaryType: "event_venue", types: ["event_venue", "point_of_interest"] }).kind).toBe("unknown");
    expect(classify({ primaryType: "point_of_interest", types: [] }).kind).toBe("unknown");
    // A bowling alley that pours and runs late is somewhere people go out.
    expect(classify({ primaryType: "bowling_alley", types: ["bar"], servesBeer: true,
                      hours: [{ day: 5, open: "16:00", close: "02:00" }] }).kind).toBe("bar");
  });

  it("keeps kava bars and pool halls, which are real college nightlife", () => {
    expect(classify({ primaryType: "tea_house", types: ["bar", "tea_house"] }).kind).toBe("bar");
    expect(classify({ primaryType: "sports_complex", types: ["bar"], servesBeer: true }).kind).toBe("bar");
  });

  it("falls back to the types array when primaryType is absent", () => {
    expect(classify({ types: ["night_club", "bar"] }).kind).toBe("club");
    expect(classify({ types: [] }).kind).toBeNull();
  });
});
