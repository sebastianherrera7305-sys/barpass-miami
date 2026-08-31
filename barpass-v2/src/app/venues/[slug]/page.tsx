import { notFound } from "next/navigation";
import Link from "next/link";
import {
  Star,
  MapPin,
  Clock,
  Music,
  Shirt,
  Car,
  ChevronLeft,
  Zap,
  Sparkles,
  Calendar,
} from "lucide-react";
import {
  getVenueBySlug,
  getVenues,
  getSimilarVenues,
} from "@/features/venues/services/venue-service";
import { VenueCard } from "@/features/venues/components/venue-card";
import { FactRow } from "@/features/venues/components/fact-row";
import { GettingThere } from "@/features/venues/components/getting-there";
import { VenuePhotos } from "@/features/venues/components/venue-photos";
import { VenueReviews } from "@/features/venues/components/venue-reviews";
import { VenueAmenities } from "@/features/venues/components/venue-amenities";
import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { formatUSD, formatTime, formatHoursRange } from "@/lib/utils";

export async function generateStaticParams() {
  const venues = await getVenues();
  return venues.map((v) => ({ slug: v.slug }));
}

export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;
  const venue = await getVenueBySlug(slug);
  return venue
    ? { title: venue.name, description: venue.hook }
    : { title: "Venue not found" };
}

export default async function VenuePage({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;
  const venue = await getVenueBySlug(slug);
  if (!venue) notFound();

  const similar = await getSimilarVenues(venue);

  return (
    <div className="mx-auto max-w-4xl px-6 pt-6">
      <Link
        href="/"
        className="mb-6 inline-flex items-center gap-1 text-sm text-text-secondary hover:text-white"
      >
        <ChevronLeft className="h-4 w-4" /> Tonight
      </Link>

      <div className="relative overflow-hidden rounded-[24px] border border-border-subtle bg-gradient-to-br from-surface-raised via-surface to-black">
        <div className="grid h-64 place-items-center text-8xl md:h-80">
          {venue.emoji}
        </div>
        <div className="absolute left-5 top-5 flex gap-2">
          {venue.isTrending && <Badge variant="live">Trending</Badge>}
          {venue.happyHourUntil && (
            <Badge variant="amber">
              Happy hour until {formatTime(venue.happyHourUntil)}
            </Badge>
          )}
        </div>
      </div>

      <div className="mt-6 flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="text-3xl font-black tracking-tight">{venue.name}</h1>
          <p className="mt-1 flex items-center gap-2 text-sm text-text-secondary">
            <MapPin className="h-3.5 w-3.5" />
            {venue.neighborhood}
            <span>·</span>
            <span className="capitalize">{venue.type.replace("_", " ")}</span>
            <span>·</span>
            {"$".repeat(venue.priceTier)}
          </p>
        </div>
        <p className="flex items-center gap-1.5 rounded-full bg-surface px-4 py-2 text-sm font-bold text-amber-brand">
          <Star className="h-4 w-4 fill-current" />
          {venue.rating}
          <span className="font-normal text-text-tertiary">
            ({venue.reviewCount.toLocaleString()})
          </span>
        </p>
      </div>

      <p className="mt-4 max-w-2xl leading-relaxed text-text-secondary">
        {venue.description}
      </p>

      {venue.live?.editorialSummary && (
        <p className="mt-3 max-w-2xl border-l-2 border-amber-brand/40 pl-3 text-sm italic text-text-tertiary">
          {venue.live.editorialSummary}{" "}
          <span className="not-italic">— Google</span>
        </p>
      )}

      <div className="mt-4 flex flex-wrap gap-2">
        {venue.vibes.map((vibe) => (
          <Badge key={vibe} variant="outline">
            {vibe}
          </Badge>
        ))}
      </div>

      {venue.live && <VenueAmenities live={venue.live} />}

      <div className="mt-8 grid gap-4 sm:grid-cols-2">
        <Card className="space-y-3 p-5">
          <h3 className="flex items-center gap-2 text-sm font-bold">
            <Clock className="h-4 w-4 text-amber-brand" /> Timing
          </h3>
          <dl className="space-y-2 text-sm">
            <FactRow
              label="Hours"
              value={formatHoursRange(venue.openTime, venue.closeTime)}
            />
            <FactRow label="Best arrival" value={venue.bestArrivalTime} />
            <FactRow label="Peak" value={venue.peakHours} />
            <FactRow
              label="Cover"
              value={
                venue.coverMen === null
                  ? "None"
                  : `${formatUSD(venue.coverMen)} M / ${formatUSD(venue.coverWomen ?? venue.coverMen)} W`
              }
            />
            <FactRow label="Avg spend" value={formatUSD(venue.avgSpend)} />
          </dl>
        </Card>

        <Card className="space-y-3 p-5">
          <h3 className="flex items-center gap-2 text-sm font-bold">
            <Music className="h-4 w-4 text-amber-brand" /> The scene
          </h3>
          <dl className="space-y-2 text-sm">
            <FactRow
              label="Music"
              value={venue.musicGenres
                .map((g) => g.replace("_", " ").toUpperCase())
                .join(" · ")}
            />
            <FactRow label="Crowd" value={venue.crowdLevel} capitalize />
            <FactRow label="Dress code" value={venue.dressCode} icon={Shirt} />
            <FactRow label="Parking" value={venue.parking} icon={Car} />
          </dl>
        </Card>
      </div>

      {venue.popularDrinks.length > 0 && (
        <section className="mt-8">
          <h3 className="text-lg font-bold">What to order</h3>
          <div className="mt-3 flex gap-3 overflow-x-auto no-scrollbar">
            {venue.popularDrinks.map((drink) => (
              <div
                key={drink.name}
                className="flex shrink-0 items-center gap-3 rounded-[16px] border border-border-subtle bg-surface px-4 py-3"
              >
                <span className="text-2xl">{drink.emoji}</span>
                <div>
                  <p className="text-sm font-semibold">{drink.name}</p>
                  <p className="text-xs text-amber-brand">
                    {formatUSD(drink.price)}
                  </p>
                </div>
              </div>
            ))}
          </div>
        </section>
      )}

      {venue.upcomingEvents.length > 0 && (
        <section className="mt-8">
          <h3 className="flex items-center gap-2 text-lg font-bold">
            <Calendar className="h-4 w-4 text-amber-brand" /> Upcoming events
          </h3>
          <div className="mt-3 space-y-3">
            {venue.upcomingEvents.map((event) => (
              <Card key={event.id} className="flex items-start gap-4 p-5">
                <span className="mt-0.5 text-2xl">📅</span>
                <div className="min-w-0 flex-1">
                  <p className="font-bold">{event.title}</p>
                  <p className="mt-1 text-sm leading-relaxed text-text-secondary">
                    {event.description}
                  </p>
                  <div className="mt-2 flex items-center gap-3 text-xs text-text-tertiary">
                    <span>
                      {new Date(event.date).toLocaleDateString("en-US", {
                        weekday: "short",
                        month: "short",
                        day: "numeric",
                        hour: "numeric",
                      })}
                    </span>
                    {event.coverPrice !== null && (
                      <span className="text-amber-brand">
                        {formatUSD(event.coverPrice)} cover
                      </span>
                    )}
                  </div>
                </div>
              </Card>
            ))}
          </div>
        </section>
      )}

      <section className="mt-8 grid gap-4 sm:grid-cols-2">
        <VenuePhotos photoRefs={venue.live?.photoRefs ?? []} />
        <VenueReviews
          rating={venue.rating}
          reviewCount={venue.reviewCount}
          reviews={venue.live?.reviews ?? []}
        />
      </section>

      <GettingThere venue={venue} />

      <div className="mt-6 flex gap-3">
        <Link
          href={`/concierge?venue=${venue.slug}`}
          className="flex flex-1 items-center justify-center gap-2 rounded-full border border-amber-brand/40 px-5 py-3 text-sm font-semibold text-amber-brand transition-colors hover:bg-amber-brand/10"
        >
          <Sparkles className="h-4 w-4" />
          Ask Remy about {venue.name}
        </Link>
        <div className="flex flex-1 items-center justify-center gap-2 rounded-full border border-dashed border-border-strong px-5 py-3 text-sm font-semibold text-text-tertiary">
          <Zap className="h-4 w-4" />
          Skip the Line — Soon
        </div>
      </div>

      {similar.length > 0 && (
        <section className="mt-12">
          <h3 className="text-lg font-bold">If you like {venue.name}…</h3>
          <div className="no-scrollbar mt-4 flex gap-4 overflow-x-auto pb-2">
            {similar.map((v) => (
              <VenueCard key={v.id} venue={v} />
            ))}
          </div>
        </section>
      )}
    </div>
  );
}
