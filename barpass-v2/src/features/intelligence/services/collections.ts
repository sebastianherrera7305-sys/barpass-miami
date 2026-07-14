import type { Venue } from "@/types";
import { getVenues } from "@/features/venues/services/venue-service";

export interface SmartCollection {
  id: string;
  title: string;
  subtitle: string;
  venues: Venue[];
}

/**
 * Deterministic, explainable groupings derived from real venue fields —
 * no invented data, no black-box scoring. Each rule is a plain filter/sort
 * over fields that already exist on every venue. A collection only ships
 * if it clears MIN_VENUES, so a sparsely-tagged dataset never renders a
 * near-empty row.
 */
const MIN_VENUES = 3;
const MAX_VENUES = 8;

function topRated(venues: Venue[]): Venue[] {
  return venues
    .filter((v) => v.rating >= 4.5)
    .sort((a, b) => b.rating - a.rating || b.reviewCount - a.reviewCount);
}

function rooftopsAndViews(venues: Venue[]): Venue[] {
  return venues
    .filter((v) => v.type === "rooftop" || v.vibes.includes("Views"))
    .sort((a, b) => b.rating - a.rating);
}

function dateNight(venues: Venue[]): Venue[] {
  return venues
    .filter(
      (v) =>
        v.vibes.includes("Date night") ||
        (["lounge", "rooftop", "restaurant"].includes(v.type) && v.crowdLevel !== "packed"),
    )
    .sort((a, b) => b.rating - a.rating);
}

function budgetFriendly(venues: Venue[]): Venue[] {
  return venues
    .filter((v) => v.priceTier <= 2)
    .sort((a, b) => a.priceTier - b.priceTier || b.rating - a.rating);
}

function liveMusicTonight(venues: Venue[]): Venue[] {
  return venues
    .filter((v) => v.musicGenres.includes("live") || v.vibes.includes("Live music"))
    .sort((a, b) => b.rating - a.rating);
}

const RULES: Array<{ id: string; title: string; subtitle: string; select: (v: Venue[]) => Venue[] }> = [
  { id: "top-rated", title: "Highly rated", subtitle: "4.5+ stars, no exceptions", select: topRated },
  { id: "rooftops", title: "Rooftops & views", subtitle: "Miami skyline, drink in hand", select: rooftopsAndViews },
  { id: "date-night", title: "Date night", subtitle: "Low-key enough to talk", select: dateNight },
  { id: "budget", title: "Easy on the wallet", subtitle: "Good night, lower spend", select: budgetFriendly },
  { id: "live-music", title: "Live music tonight", subtitle: "Bands, not just DJs", select: liveMusicTonight },
];

export async function getSmartCollections(): Promise<SmartCollection[]> {
  const venues = await getVenues();

  return RULES.map((rule) => ({
    id: rule.id,
    title: rule.title,
    subtitle: rule.subtitle,
    venues: rule.select(venues).slice(0, MAX_VENUES),
  })).filter((c) => c.venues.length >= MIN_VENUES);
}
