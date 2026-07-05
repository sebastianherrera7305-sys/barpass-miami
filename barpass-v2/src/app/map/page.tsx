import type { Metadata } from "next";
import { getVenues } from "@/features/venues/services/venue-service";
import { VenueMap } from "@/features/map/components/venue-map";

export const metadata: Metadata = {
  title: "Live Map",
  description: "Explore Miami nightlife on a live map — trending venues, happy hours, rooftops and hidden gems.",
};

/** Live nightlife map — venues stream in from the same service layer. */
export default async function MapPage() {
  const venues = await getVenues();
  return <VenueMap venues={venues} />;
}
