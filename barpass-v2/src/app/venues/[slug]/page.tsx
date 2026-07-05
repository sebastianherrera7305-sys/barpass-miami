import { notFound } from "next/navigation";
import Link from "next/link";
import {
  Star,
  MapPin,
  Clock,
  Shirt,
  Car,
  Music,
  Camera,
  ChevronLeft,
  Zap,
} from "lucide-react";
import {
  getVenueBySlug,
  getVenues,
  getSimilarVenues,
} from "@/features/venues/services/venue-service";
import { VenueCard } from "@/features/venues/components/venue-card";
import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { formatUSD, formatTime } from "@/lib/utils";

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

/**
 * Venue detail — better than Yelp.
 * Static-generated per venue; every fact a night-out decision needs
 * above the fold, editorial voice throughout.
 */
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

      {/* Hero */}
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

      {/* Title block */}
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

      {/* Vibes */}
      <div className="mt-4 flex flex-wrap gap-2">
        {venue.vibes.map((vibe) => (
          <Badge key={vibe} variant="outline">
            {vibe}
          </Badge>
        ))}
      </div>

      {/* Facts grid */}
      <div className="mt-8 grid gap-4 sm:grid-cols-2">
        <Card className="space-y-3 p-5">
          <h3 className="flex items-center gap-2 text-sm font-bold">
            <Clock className="h-4 w-4 text-amber-brand" /> Timing
          </h3>
          <dl className="space-y-2 text-sm">
            <FactRow
              label="Hours"
              value={`${formatTime(venue.openTime)} – ${formatTime(venue.closeTime)}`}
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

      {/* Popular drinks */}
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

      {/* Location + links */}
      <Card className="mt-8 flex flex-wrap items-center justify-between gap-4 p-5">
        <div>
          <p className="text-sm font-semibold">{venue.address}</p>
          {venue.instagramHandle && (
            <a
              href={`https://instagram.com/${venue.instagramHandle}`}
              target="_blank"
              rel="noopener noreferrer"
              className="mt-1 inline-flex items-center gap-1 text-xs text-text-secondary hover:text-amber-brand"
            >
              <Camera className="h-3 w-3" /> @{venue.instagramHandle}
            </a>
          )}
        </div>
        <a
          href={`https://maps.google.com/?q=${encodeURIComponent(venue.address)}`}
          target="_blank"
          rel="noopener noreferrer"
          className="rounded-full border border-amber-brand/40 px-5 py-2 text-sm font-semibold text-amber-brand hover:bg-amber-brand/10"
        >
          Directions
        </a>
      </Card>

      {/* Skip the Line — coming soon */}
      <div className="mt-8 flex items-center justify-between rounded-[20px] border border-dashed border-border-strong px-6 py-5">
        <div className="flex items-center gap-3">
          <Zap className="h-5 w-5 text-text-tertiary" />
          <div>
            <p className="font-semibold text-text-secondary">Skip the Line</p>
            <p className="text-xs text-text-tertiary">
              Priority entry at {venue.name} — coming soon
            </p>
          </div>
        </div>
        <Badge>Soon</Badge>
      </div>

      {/* Similar venues */}
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

function FactRow({
  label,
  value,
  capitalize,
}: {
  label: string;
  value: string;
  icon?: React.ComponentType<{ className?: string }>;
  capitalize?: boolean;
}) {
  return (
    <div className="flex items-baseline justify-between gap-4">
      <dt className="shrink-0 text-text-tertiary">{label}</dt>
      <dd
        className={`text-right font-medium ${capitalize ? "capitalize" : ""}`}
      >
        {value}
      </dd>
    </div>
  );
}
