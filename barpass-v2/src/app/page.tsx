import Link from "next/link";
import { Sparkles, ArrowRight, Calendar } from "lucide-react";
import {
  getTrendingVenues,
  getHappyHourVenues,
  getVenuesByNeighborhood,
  getAllEvents,
  isServingLiveData,
} from "@/features/venues/services/venue-service";
import { VenueRow } from "@/features/discover/components/venue-row";
import { getSmartCollections } from "@/features/intelligence/services/collections";
import { formatUSD } from "@/lib/utils";

export default async function DiscoverPage() {
  const [trending, happyHour, byNeighborhood, events, collections] =
    await Promise.all([
      getTrendingVenues(),
      getHappyHourVenues(),
      getVenuesByNeighborhood(),
      getAllEvents(),
      getSmartCollections(),
    ]);
  const isLive = isServingLiveData();

  return (
    <div className="mx-auto max-w-6xl space-y-10 pt-8">
      {!isLive && (
        <div className="mx-6 rounded-2xl border border-amber-brand/30 bg-amber-brand/10 px-4 py-3 text-sm text-amber-brand">
          Showing demo data — live venue info is temporarily unavailable.
        </div>
      )}
      <section className="px-6">
        <p className="text-[11px] font-bold uppercase tracking-[4px] text-amber-brand">
          Miami · Tonight
        </p>
        <h1 className="mt-2 max-w-xl text-3xl font-black leading-tight tracking-tight md:text-4xl">
          What should we do tonight?
        </h1>

        <Link
          href="/concierge"
          className="group mt-6 flex items-center justify-between rounded-[20px] border border-amber-brand/25 bg-gradient-to-r from-amber-brand/10 to-transparent px-6 py-5 transition-colors hover:border-amber-brand/50"
        >
          <div className="flex items-center gap-4">
            <span className="grid h-11 w-11 place-items-center rounded-full bg-amber-brand/15">
              <Sparkles className="h-5 w-5 text-amber-brand" />
            </span>
            <div>
              <p className="font-bold">Ask the Concierge</p>
              <p className="text-sm text-text-secondary">
                &ldquo;First date, $100, we love rooftops&rdquo; → a full plan
              </p>
            </div>
          </div>
          <ArrowRight className="h-5 w-5 text-amber-brand transition-transform group-hover:translate-x-1" />
        </Link>
      </section>

      {events.length > 0 && (
        <section className="overflow-hidden px-6">
          <div className="mb-4 flex items-center gap-2">
            <Calendar className="h-4 w-4 text-amber-brand" />
            <h2 className="text-lg font-bold">Events tonight</h2>
          </div>
          <div className="no-scrollbar flex gap-4 overflow-x-auto pb-2">
            {events.map(({ venueName, venueSlug, venueEmoji, event }) => (
              <Link
                key={event.id}
                href={`/venues/${venueSlug}`}
                className="group w-[240px] shrink-0 snap-start"
              >
                <div className="overflow-hidden rounded-[20px] border border-border-subtle bg-gradient-to-br from-surface-raised to-surface transition-transform duration-300 group-hover:scale-[1.02]">
                  <div className="grid h-24 place-items-center bg-gradient-to-br from-amber-brand/8 to-transparent text-4xl">
                    {venueEmoji}
                  </div>
                  <div className="space-y-2 p-4">
                    <p className="text-sm font-bold leading-tight">
                      {event.title}
                    </p>
                    <p className="line-clamp-2 text-xs leading-relaxed text-text-secondary">
                      {event.description}
                    </p>
                    <div className="flex items-center justify-between pt-1 text-xs text-text-tertiary">
                      <span>at {venueName}</span>
                      {event.coverPrice !== null && (
                        <span className="text-amber-brand">
                          {formatUSD(event.coverPrice)}
                        </span>
                      )}
                    </div>
                  </div>
                </div>
              </Link>
            ))}
          </div>
        </section>
      )}

      <VenueRow
        title="Trending tonight"
        subtitle="Where Miami is actually going"
        venues={trending}
      />
      <VenueRow
        title="Happy hour now"
        subtitle="Drink well, pay less"
        venues={happyHour}
      />

      {/* BarPass Intelligence — collections derived from real signals */}
      {collections.map((c) => (
        <VenueRow
          key={c.id}
          title={c.title}
          subtitle={c.subtitle}
          venues={c.venues}
        />
      ))}

      {Array.from(byNeighborhood.entries()).map(([neighborhood, venues]) => (
        <VenueRow key={neighborhood} title={neighborhood} venues={venues} />
      ))}
    </div>
  );
}
