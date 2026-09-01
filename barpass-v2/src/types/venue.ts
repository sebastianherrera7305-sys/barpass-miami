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

/// Must stay in sync with `MusicGenre` in
/// BarPass-iOS/BarPass/Models/Venue.swift, which carries the rationale for
/// each term. This list had drifted: it still lacked country, rock, blues,
/// afrobeats and tech_house months after iOS gained them, so the web silently
/// widened its own type every time the database held a value it did not know.
/// `live` is a performance format and composes with a genre.
export type MusicGenre =
  | "edm"
  | "house"
  | "tech_house"
  | "techno"
  | "disco"
  | "latin"
  | "salsa"
  | "bachata"
  | "reggaeton"
  | "hip_hop"
  | "rnb"
  | "soul"
  | "funk"
  | "pop"
  | "live"
  | "jazz"
  | "blues"
  | "country"
  | "americana"
  | "rock"
  | "goth"
  | "reggae"
  | "dancehall"
  | "afrobeats"
  | "amapiano"
  | "soca"
  | "tejano";

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
  /// Real end time (ISO) when the source actually knows it — null, not an
  /// invented time, when it doesn't.
  endDate: string | null;
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
  /**
   * null when unknown. 1665 of 1832 served venues have no real figure (only
   * the 167 fabricated Miami seed rows ever had one), and 0 was rendering as
   * a confident "$0" on every one of them. iOS already showed "N/A" here;
   * the web was the odd one out.
   */
  avgSpend: number | null;

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

  /**
   * LIVE layer — populated by the Google Places enrichment script.
   * Absent until a venue has been verified against Google. When present,
   * `businessStatus` is the source of truth for whether the venue still
   * exists (this is what would have caught The Wharf).
   */
  live?: VenueLiveMeta;
}

export type BusinessStatus =
  | "OPERATIONAL"
  | "CLOSED_TEMPORARILY"
  | "CLOSED_PERMANENTLY";

/** A single real Google review — never fabricated. */
export interface LiveReview {
  author: string;
  authorPhoto: string | null;
  rating: number;
  text: string;
  relativeTime: string; // "5 months ago"
}

/**
 * Amenities as reported by Google. A field is only present when Google
 * actually knows it — absent means "unknown", never "false". The UI must
 * treat `undefined` as "don't show", not as a negative.
 */
export interface LiveAmenities {
  reservable?: boolean;
  outdoorSeating?: boolean;
  liveMusic?: boolean;
  goodForGroups?: boolean;
  servesCocktails?: boolean;
  servesBeer?: boolean;
  servesWine?: boolean;
  restroom?: boolean;
  wheelchairAccessible?: boolean;
}

export type PriceLevel =
  | "PRICE_LEVEL_INEXPENSIVE"
  | "PRICE_LEVEL_MODERATE"
  | "PRICE_LEVEL_EXPENSIVE"
  | "PRICE_LEVEL_VERY_EXPENSIVE";

export interface VenueLiveMeta {
  placeId: string;
  businessStatus: BusinessStatus;
  googleMapsUri: string | null;
  weekdayText: string[];
  photoRefs: string[];
  /** ISO timestamp of the last successful Google verification. */
  lastVerified: string;

  /** Google's own one-line editorial description, when available. */
  editorialSummary: string | null;
  primaryType: string | null;
  priceLevel: PriceLevel | null;
  phone: string | null;
  website: string | null;
  amenities: LiveAmenities;
  reviews: LiveReview[];
}
