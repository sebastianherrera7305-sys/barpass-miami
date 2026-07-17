import { describe, it, expect } from "vitest";
import { deriveExperienceTags, type VenueSignals } from "./experience-tags-rules";

function signals(overrides: Partial<VenueSignals> = {}): VenueSignals {
  return {
    type: "bar",
    hasHappyHour: false,
    wheelchairAccessible: null,
    outdoorSeating: null,
    goodForGroups: null,
    goodForWatchingSports: null,
    hasLiveMusic: null,
    reservable: null,
    servesVegetarianFood: null,
    ...overrides,
  };
}

function tagIds(v: VenueSignals) {
  return deriveExperienceTags(v).map((t) => t.id).sort();
}

describe("deriveExperienceTags", () => {
  it("emits no tags when every signal is unknown (never invents a tag from absence of data)", () => {
    expect(deriveExperienceTags(signals())).toEqual([]);
  });

  it("emits no tags when a signal is explicitly false, not just unknown", () => {
    const v = signals({ hasLiveMusic: false, goodForGroups: false, outdoorSeating: false });
    expect(deriveExperienceTags(v)).toEqual([]);
  });

  it("maps a single Google attribute to a high-confidence, single-source tag", () => {
    const tags = deriveExperienceTags(signals({ hasLiveMusic: true }));
    expect(tags).toEqual([
      { id: "live_music", category: "music", confidence: "high", source: "google_attribute" },
    ]);
  });

  it("wheelchair accessibility, sports viewing, and vegetarian food all map high/google_attribute", () => {
    const v = signals({ wheelchairAccessible: true, goodForWatchingSports: true, servesVegetarianFood: true });
    const tags = deriveExperienceTags(v);
    for (const t of tags) {
      expect(t.confidence).toBe("high");
      expect(t.source).toBe("google_attribute");
    }
    expect(tagIds(v)).toEqual(["accessible", "sports_viewing", "vegetarian_friendly"]);
  });

  it("combines an attribute + category into a medium-confidence tag neither confirms alone", () => {
    // reservable alone, wrong category — should NOT produce date_friendly.
    expect(tagIds(signals({ reservable: true, type: "club" }))).toEqual(["high_energy"]);
    // reservable + a date-friendly category — should.
    const tags = deriveExperienceTags(signals({ reservable: true, type: "restaurant" }));
    expect(tags).toContainEqual({
      id: "date_friendly",
      category: "social",
      confidence: "medium",
      source: "venue_category",
    });
  });

  it("good_for_groups only becomes 'social' in a social-leaning category", () => {
    expect(tagIds(signals({ goodForGroups: true, type: "restaurant" }))).toEqual(["group_night"]);
    expect(tagIds(signals({ goodForGroups: true, type: "club" }))).toEqual(["group_night", "high_energy", "social"].sort());
  });

  it("category-only rules (club/rooftop/happy hour) are always medium confidence, never high", () => {
    for (const v of [signals({ type: "club" }), signals({ type: "rooftop" }), signals({ hasHappyHour: true })]) {
      for (const t of deriveExperienceTags(v)) expect(t.confidence).toBe("medium");
    }
  });

  it("never emits 'low' confidence — no weak-inference input exists yet in this rule set", () => {
    const allPossibleTrue = signals({
      wheelchairAccessible: true,
      outdoorSeating: true,
      goodForGroups: true,
      goodForWatchingSports: true,
      hasLiveMusic: true,
      reservable: true,
      servesVegetarianFood: true,
      hasHappyHour: true,
      type: "rooftop",
    });
    const confidences = deriveExperienceTags(allPossibleTrue).map((t) => t.confidence);
    expect(confidences).not.toContain("low");
  });

  it("a fully-populated venue produces the expected full tag set, order-independent", () => {
    const v = signals({
      goodForGroups: true,
      hasLiveMusic: true,
      reservable: true,
      outdoorSeating: true,
      type: "restaurant",
    });
    expect(tagIds(v)).toEqual(
      ["date_friendly", "group_night", "live_music", "outdoor_experience"].sort()
    );
  });
});
