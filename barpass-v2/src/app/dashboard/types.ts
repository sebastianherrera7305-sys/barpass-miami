/** Shapes returned by /api/venue-owner/venues[/:id], as the dashboard sees them. */

export interface OwnedVenueSummary {
  id: string;
  role: string;
  name: string;
  slug: string;
  city: string | null;
  listed: boolean;
}

export interface DayHours {
  day: number;
  label: string;
  periods: Array<{ open: string; close: string }>;
  closed: boolean;
}

export interface OwnerVenue {
  id: string;
  slug: string;
  name: string;
  type: string;
  city: string | null;
  neighborhood: string | null;
  address: string | null;
  phone: string | null;
  website: string | null;
  instagramHandle: string | null;
  imageUrl: string | null;
  agePolicy: string | null;
  priceTier: number | null;
  avgSpend: number | null;
  coverMen: number | null;
  coverWomen: number | null;
  openTime: string | null;
  closeTime: string | null;
  happyHourUntil: string | null;
  dressCode: string | null;
  parking: string | null;
  timezone: string | null;
  musicGenres: string[];
  vibes: string[];
  hours: DayHours[] | null;
  drinks: Array<{ name: string; price: number; emoji: string }>;
  drinksSource: { url: string | null; date: string | null } | null;
  amenities: Record<string, boolean | null>;
  googleSyncedAt: string | null;
  visibility: { listed: boolean; reason: string | null; businessStatus: string | null };
}

export interface VenueEventRow {
  id: string;
  title: string;
  description: string;
  startsAt: string;
  endsAt: string | null;
  coverPrice: number | null;
}

export interface PromoRow {
  id: string;
  title: string;
  description: string | null;
  startsAt: string;
  endsAt: string | null;
  discountText: string | null;
}

export interface HostEventRow {
  id: string;
  title: string;
  startsAt: string;
  endsAt: string | null;
  hostType: "promoter" | "venue";
  hostName: string | null;
}

export interface OwnerDashboardData {
  role: string;
  venue: OwnerVenue;
  tonight: {
    revenue: number;
    orders: number;
    passesIssued: number;
    passesRedeemed: number;
    guestsOnPasses: number;
  };
  recentPasses: Array<{
    id: string;
    kind: string;
    quantity: number;
    amount: number;
    redeemedAt: string | null;
    createdAt: string;
  }>;
  events: VenueEventRow[];
  eventsUnavailable: boolean;
  promos: PromoRow[];
  promosUnavailable: boolean;
  hostEvents: HostEventRow[];
  hostEventsUnavailable: boolean;
}
