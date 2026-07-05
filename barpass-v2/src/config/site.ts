/**
 * Global site configuration.
 * Single source of truth for product identity — never hardcode these
 * strings inside components.
 */
export const siteConfig = {
  name: "BarPass",
  tagline: "The smartest nightlife companion in Miami",
  description:
    "Discover venues, plan your night, and let the AI Concierge build the perfect itinerary — bars, rooftops, clubs and events across Miami.",
  url: "https://barpass.app",
  city: "Miami",
  launchDate: "2026-08-15",
  links: {
    instagram: "https://instagram.com/barpass",
    support: "mailto:hola@barpass.app",
  },
} as const;

export type SiteConfig = typeof siteConfig;
