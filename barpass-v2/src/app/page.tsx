import Link from "next/link";
import { Sparkles, ArrowRight } from "lucide-react";
import {
  getTrendingVenues,
  getHappyHourVenues,
  getVenuesByNeighborhood,
} from "@/features/venues/services/venue-service";
import { VenueRow } from "@/features/discover/components/venue-row";

/**
 * Discover — the home screen.
 * Answers one question: "What should I do tonight?"
 * Server Component: venue rows render on the server, instantly.
 */
export default async function DiscoverPage() {
  const [trending, happyHour, byNeighborhood] = await Promise.all([
    getTrendingVenues(),
    getHappyHourVenues(),
    getVenuesByNeighborhood(),
  ]);

  return (
    <div className="mx-auto max-w-6xl space-y-10 pt-8">
      {/* Hero */}
      <section className="px-6">
        <p className="text-[11px] font-bold uppercase tracking-[4px] text-amber-brand">
          Miami · Tonight
        </p>
        <h1 className="mt-2 max-w-xl text-3xl font-black leading-tight tracking-tight md:text-4xl">
          What should we do tonight?
        </h1>

        {/* Concierge entry point — the product's front door */}
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

      {/* Curated rows */}
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

      {Array.from(byNeighborhood.entries()).map(([neighborhood, venues]) => (
        <VenueRow key={neighborhood} title={neighborhood} venues={venues} />
      ))}
    </div>
  );
}
