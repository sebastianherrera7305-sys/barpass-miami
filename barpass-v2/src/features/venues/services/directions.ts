import type { Venue } from "@/types";

/**
 * Directions / ride providers for a venue.
 *
 * Returns ready-to-use deep links so the UI stays dumb. Adding Lyft, transit,
 * etc. later means appending one entry here — no component changes. Uber is
 * marked `primary` and uses its universal link: opens the Uber app with the
 * destination prefilled when installed, else falls back to Uber mobile web.
 */
export type DirectionsProviderId = "uber" | "apple_maps" | "google_maps";

export interface DirectionsProvider {
  id: DirectionsProviderId;
  label: string;
  href: string;
  primary?: boolean;
}

export function getDirectionsProviders(venue: Venue): DirectionsProvider[] {
  const { lat, lng, name, address } = venue;
  const nickname = encodeURIComponent(name);
  const formattedAddress = encodeURIComponent(address);
  const query = encodeURIComponent(name);

  return [
    {
      id: "uber",
      label: "Ride with Uber",
      primary: true,
      href:
        "https://m.uber.com/ul/?action=setPickup&pickup=my_location" +
        `&dropoff[latitude]=${lat}&dropoff[longitude]=${lng}` +
        `&dropoff[nickname]=${nickname}` +
        `&dropoff[formatted_address]=${formattedAddress}`,
    },
    {
      id: "apple_maps",
      label: "Apple Maps",
      href: `https://maps.apple.com/?daddr=${lat},${lng}&q=${query}&dirflg=d`,
    },
    {
      id: "google_maps",
      label: "Google Maps",
      href: `https://www.google.com/maps/dir/?api=1&destination=${lat},${lng}`,
    },
  ];
}
