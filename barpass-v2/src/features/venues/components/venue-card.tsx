import Link from "next/link";
import { Star, MapPin } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { formatUSD, formatTime } from "@/lib/utils";
import type { Venue } from "@/types";

/**
 * Primary venue card used in Discover rows and collection grids.
 * Server Component — zero JS shipped for the card itself.
 */
export function VenueCard({ venue }: { venue: Venue }) {
  const cover =
    venue.coverMen === null
      ? "No cover"
      : `${formatUSD(Math.min(venue.coverMen, venue.coverWomen ?? venue.coverMen))}+ cover`;

  return (
    <Link
      href={`/venues/${venue.slug}`}
      className="group block w-[270px] shrink-0 snap-start"
    >
      {/* Visual */}
      <div className="relative h-[170px] overflow-hidden rounded-[20px] border border-border-subtle bg-gradient-to-br from-surface-raised to-surface transition-transform duration-300 group-hover:scale-[1.02]">
        <span className="absolute inset-0 grid place-items-center text-6xl opacity-80">
          {venue.emoji}
        </span>

        <div className="absolute left-3 top-3 flex gap-1.5">
          {venue.isTrending && <Badge variant="live">Trending</Badge>}
          {venue.happyHourUntil && (
            <Badge variant="amber">HH until {formatTime(venue.happyHourUntil)}</Badge>
          )}
        </div>

        <div className="absolute inset-x-0 bottom-0 h-16 bg-gradient-to-t from-black/70 to-transparent" />
      </div>

      {/* Meta */}
      <div className="mt-3 space-y-1 px-0.5">
        <h3 className="text-[15px] font-bold leading-tight">{venue.name}</h3>
        <p className="flex items-center gap-1 text-[12px] text-text-tertiary">
          <MapPin className="h-3 w-3" />
          {venue.neighborhood}
          <span className="px-0.5">·</span>
          {venue.hook}
        </p>
        <p className="flex items-center gap-1.5 text-[12px] text-text-secondary">
          <span className="flex items-center gap-0.5 font-semibold text-amber-brand">
            <Star className="h-3 w-3 fill-current" />
            {venue.rating}
          </span>
          <span className="text-text-tertiary">·</span>
          {cover}
          <span className="text-text-tertiary">·</span>
          {"$".repeat(venue.priceTier)}
        </p>
      </div>
    </Link>
  );
}
