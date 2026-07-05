import type { Venue, Neighborhood } from "@/types";
import { VENUES } from "../data/venues";

/**
 * Venue data access layer.
 *
 * Every venue read in the app goes through this module — pages, the AI
 * concierge, the map, and collections all call these functions. When the
 * Supabase `venues` table goes live, only this file changes.
 */

export async function getVenues(): Promise<Venue[]> {
  return VENUES;
}

export async function getVenueBySlug(slug: string): Promise<Venue | null> {
  return VENUES.find((v) => v.slug === slug) ?? null;
}

export async function getTrendingVenues(): Promise<Venue[]> {
  return VENUES.filter((v) => v.isTrending);
}

export async function getHappyHourVenues(): Promise<Venue[]> {
  return VENUES.filter((v) => v.happyHourUntil !== null);
}

export async function getVenuesByNeighborhood(): Promise<
  Map<Neighborhood, Venue[]>
> {
  const grouped = new Map<Neighborhood, Venue[]>();
  for (const venue of VENUES) {
    const list = grouped.get(venue.neighborhood) ?? [];
    list.push(venue);
    grouped.set(venue.neighborhood, list);
  }
  return grouped;
}

export async function getSimilarVenues(venue: Venue, limit = 3): Promise<Venue[]> {
  return VENUES.filter(
    (v) =>
      v.id !== venue.id &&
      (v.type === venue.type || v.neighborhood === venue.neighborhood),
  ).slice(0, limit);
}
