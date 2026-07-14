import type { VenueLiveMeta } from "@/types";

interface VenueAmenitiesProps {
  live: VenueLiveMeta;
}

const amenityLabels: Array<[keyof VenueLiveMeta["amenities"], string]> = [
  ["reservable", "Reservations"],
  ["outdoorSeating", "Outdoor seating"],
  ["liveMusic", "Live music"],
  ["goodForGroups", "Good for groups"],
  ["servesCocktails", "Cocktails"],
  ["servesBeer", "Beer"],
  ["servesWine", "Wine"],
  ["restroom", "Restroom"],
  ["wheelchairAccessible", "Wheelchair accessible"],
];

export function VenueAmenities({ live }: VenueAmenitiesProps) {
  const enabled = amenityLabels.filter(([key]) => live.amenities[key]);

  if (enabled.length === 0) {
    return null;
  }

  return (
    <div className="mt-6 rounded-[20px] border border-border-subtle bg-surface p-5">
      <h3 className="text-sm font-bold">Amenities</h3>
      <div className="mt-3 flex flex-wrap gap-2">
        {enabled.map(([key, label]) => (
          <span key={String(key)} className="rounded-full border border-amber-brand/30 bg-amber-brand/10 px-3 py-1 text-sm text-amber-brand">
            {label}
          </span>
        ))}
      </div>
    </div>
  );
}
