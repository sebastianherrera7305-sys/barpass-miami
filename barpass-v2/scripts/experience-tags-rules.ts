/**
 * Deterministic Experience Tag derivation — the "Venue Intelligence Layer"
 * rule engine. Pure function of data BarPass already has (Phase 1 amenity
 * booleans + venue type + happy_hour), zero external calls, zero
 * randomness, zero AI. Every rule is documented here so a tag's source and
 * confidence can always be traced back to a real signal.
 *
 * Confidence discipline (never claim more certainty than the input allows):
 *  - "high"   → a single, direct Google-sourced attribute is true.
 *  - "medium" → an attribute + venue category combine to suggest something
 *               neither alone confirms (e.g. reservable + restaurant type
 *               suggests "date friendly", but reservable alone doesn't).
 *  - "low"    → reserved for future AI-derived tags; the rule engine below
 *               never emits "low" itself — there's no weak-inference input
 *               yet, and this file must not invent one.
 */

export type TagConfidence = "high" | "medium" | "low";
export type TagSource = "google_attribute" | "venue_category" | "user_signal" | "future_ai";

export interface ExperienceTag {
  id: string;
  category: string;
  confidence: TagConfidence;
  source: TagSource;
}

/** The subset of a venue row this rule engine actually reads. */
export interface VenueSignals {
  type: string;
  hasHappyHour: boolean;
  wheelchairAccessible: boolean | null;
  outdoorSeating: boolean | null;
  goodForGroups: boolean | null;
  goodForWatchingSports: boolean | null;
  hasLiveMusic: boolean | null;
  reservable: boolean | null;
  servesVegetarianFood: boolean | null;
}

const DATE_FRIENDLY_TYPES = new Set(["restaurant", "rooftop", "lounge"]);
const SOCIAL_TYPES = new Set(["bar", "lounge", "club"]);

/**
 * Runs every rule against one venue's signals and returns the tags that
 * apply. Order doesn't matter — each rule is independent and additive.
 */
export function deriveExperienceTags(v: VenueSignals): ExperienceTag[] {
  const tags: ExperienceTag[] = [];
  const add = (id: string, category: string, confidence: TagConfidence, source: TagSource) =>
    tags.push({ id, category, confidence, source });

  // Direct Google attribute → high confidence, single signal.
  if (v.hasLiveMusic === true) add("live_music", "music", "high", "google_attribute");
  if (v.goodForGroups === true) add("group_night", "social", "high", "google_attribute");
  if (v.outdoorSeating === true) add("outdoor_experience", "atmosphere", "high", "google_attribute");
  if (v.goodForWatchingSports === true) add("sports_viewing", "atmosphere", "high", "google_attribute");
  if (v.wheelchairAccessible === true) add("accessible", "accessibility", "high", "google_attribute");
  if (v.servesVegetarianFood === true) add("vegetarian_friendly", "food", "high", "google_attribute");

  // Attribute + category combine into a suggestion neither confirms alone
  // → medium confidence, per the brief's own "restaurant + outdoor =
  // possible date" example.
  if (v.goodForGroups === true && SOCIAL_TYPES.has(v.type)) {
    add("social", "social", "medium", "venue_category");
  }
  if (v.reservable === true && DATE_FRIENDLY_TYPES.has(v.type)) {
    add("date_friendly", "social", "medium", "venue_category");
  }

  // Category-only inference → medium confidence (the type itself is real
  // data, but "club implies high energy" is a category generalization, not
  // a per-venue fact the way a Google attribute is).
  if (v.type === "club") add("high_energy", "atmosphere", "medium", "venue_category");
  if (v.type === "rooftop") add("scenic", "atmosphere", "medium", "venue_category");
  if (v.hasHappyHour) add("budget_friendly", "value", "medium", "venue_category");

  return tags;
}
