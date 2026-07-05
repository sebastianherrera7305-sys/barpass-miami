import { VenueCard } from "@/features/venues/components/venue-card";
import type { Venue } from "@/types";

/**
 * Horizontal snap-scroll row of venues under a section heading.
 * The core layout primitive of the Discover page.
 */
export function VenueRow({
  title,
  subtitle,
  venues,
}: {
  title: string;
  subtitle?: string;
  venues: Venue[];
}) {
  if (venues.length === 0) return null;

  return (
    <section className="space-y-4">
      <div className="px-6">
        <h2 className="text-xl font-bold tracking-tight">{title}</h2>
        {subtitle && (
          <p className="mt-0.5 text-sm text-text-tertiary">{subtitle}</p>
        )}
      </div>
      <div className="no-scrollbar flex snap-x gap-4 overflow-x-auto px-6 pb-2">
        {venues.map((venue) => (
          <VenueCard key={venue.id} venue={venue} />
        ))}
      </div>
    </section>
  );
}
