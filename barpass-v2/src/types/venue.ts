/**
 * Core venue domain types.
 * Mirrors the `venues` table in Supabase (see supabase/schema.sql).
 * The iOS app consumes the same shape through the Supabase REST API.
 */

export type VenueType =
  | "club"
  | "rooftop"
  | "bar"
  | "lounge"
  | "sports_bar"
  | "restaurant"
  | "brewery";

export type MusicGenre =
  | "edm"
  | "house"
  | "techno"
  | "latin"
  | "reggaeton"
  | "hip_hop"
  | "rnb"
  | "pop"
  | "live"
  | "jazz";

export type Neighborhood =
  | "South Beach"
  | "Brickell"
  | "Wynwood"
  | "Downtown"
  | "Little Havana"
  | "Design District"
  | "Coconut Grove";

export type CrowdLevel = "quiet" | "steady" | "busy" | "packed";

export type PriceTier = 1 | 2 | 3 | 4; // $ → $$$$

export interface PopularDrink {
  name: string;
  price: number;
  emoji: string;
}

export interface VenueEvent {
  id: string;
  title: string;
  date: string; // ISO
  coverPrice: number | null;
  description: string;
}

export interface Venue {
  id: string;
  slug: string;
  name: string;
  type: VenueType;
  neighborhood: Neighborhood;
  address: string;
  lat: number;
  lng: number;

  /** Short editorial one-liner shown on cards. */
  hook: string;
  description: string;

  rating: number;
  reviewCount: number;

  coverMen: number | null;
  coverWomen: number | null;
  priceTier: PriceTier;
  avgSpend: number;

  openTime: string; // "22:00"
  closeTime: string; // "05:00"
  happyHourUntil: string | null;

  musicGenres: MusicGenre[];
  vibes: string[];
  dressCode: string;
  parking: string;

  crowdLevel: CrowdLevel;
  bestArrivalTime: string;
  peakHours: string;

  popularDrinks: PopularDrink[];
  upcomingEvents: VenueEvent[];

  emoji: string;
  imageUrl: string | null;
  instagramHandle: string | null;

  isTrending: boolean;
  isOpenNow: boolean;
}
