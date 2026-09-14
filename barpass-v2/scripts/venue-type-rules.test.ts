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

  it("rejects things that are not venues at all", () => {
    for (const p of ["liquor_store", "farm", "indoor_golf_course",
                     "performing_arts_theater", "store", "bowling_alley"]) {
      expect(classify({ primaryType: p, types: ["bar"] }).kind).toBeNull();
    }
  });

  it("lets a warehouse that actually runs club nights through", () => {
    expect(classify({ primaryType: "event_venue", types: ["night_club", "event_venue"], servesBeer: true }).kind).toBe("club");
    expect(classify({ primaryType: "event_venue", types: ["event_venue"] }).kind).toBeNull();
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
