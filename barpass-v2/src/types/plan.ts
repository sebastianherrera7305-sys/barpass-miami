/**
 * AI Concierge itinerary types.
 * A NightPlan is the structured output of the concierge — every stop
 * references a real venue so the UI can deep-link into venue pages.
 */

export interface PlanStop {
  time: string; // "9:30 PM"
  venueSlug: string;
  venueName: string;
  note: string; // why this stop, what to order, insider tip
  estimatedSpend: number;
}

export interface NightPlan {
  title: string;
  summary: string;
  stops: PlanStop[];
  totalEstimate: number;
  insiderTip: string;
}

/** What the user tells the concierge — free text plus optional structure. */
export interface ConciergeRequest {
  prompt: string;
  budget?: number;
  groupSize?: number;
  neighborhood?: string;
}
