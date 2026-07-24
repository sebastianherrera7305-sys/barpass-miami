import { notFound } from "next/navigation";
import Link from "next/link";
import { Calendar, MapPin, Users, ChevronLeft } from "lucide-react";
import { getTripPreview } from "@/features/trips/services/trip-preview-service";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { siteConfig } from "@/config/site";

// Dynamic — trip previews are per-invitation, not a static, enumerable set
// (unlike venues), so this route intentionally has no generateStaticParams.

function formatDateRange(startISO: string, endISO: string): string {
  const fmt = new Intl.DateTimeFormat("es-MX", { day: "numeric", month: "short" });
  return `${fmt.format(new Date(startISO))} – ${fmt.format(new Date(endISO))}`;
}

export async function generateMetadata({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const trip = await getTripPreview(id);
  if (!trip) return { title: "Trip not found" };

  const title = `${trip.title} · BarPass`;
  const description = `${trip.destinationCity} · ${formatDateRange(trip.startDate, trip.endDate)} · ${trip.memberCount} ${trip.memberCount === 1 ? "persona" : "personas"}`;
  return {
    title,
    description,
    openGraph: {
      title,
      description,
      images: trip.coverImage ? [{ url: trip.coverImage }] : undefined,
    },
    twitter: { card: "summary_large_image", title, description },
  };
}

export default async function TripLandingPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const trip = await getTripPreview(id);
  if (!trip) notFound();

  const deepLink = `barpass://trip/${id}`;

  return (
    <div className="mx-auto max-w-lg px-6 pt-6">
      <Link
        href="/"
        className="mb-6 inline-flex items-center gap-1 text-sm text-text-secondary hover:text-white"
      >
        <ChevronLeft className="h-4 w-4" /> {siteConfig.name}
      </Link>

      <div className="relative overflow-hidden rounded-[24px] border border-border-subtle bg-gradient-to-br from-surface-raised via-surface to-black">
        <div className="grid h-56 place-items-center text-7xl">
          {trip.coverImage ? (
            // Remote, user-supplied cover images — no static domain list configured yet.
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={trip.coverImage}
              alt={trip.title}
              className="h-full w-full object-cover"
            />
          ) : (
            "🌴"
          )}
        </div>
      </div>

      <h1 className="mt-6 text-3xl font-black tracking-tight">{trip.title}</h1>
      <p className="mt-2 flex flex-wrap items-center gap-2 text-sm text-text-secondary">
        <MapPin className="h-3.5 w-3.5" />
        {trip.destinationCity}
        <span>·</span>
        <Calendar className="h-3.5 w-3.5" />
        {formatDateRange(trip.startDate, trip.endDate)}
      </p>

      <div className="mt-3 flex flex-wrap gap-2">
        <Badge variant="outline">
          <Users className="mr-1 h-3 w-3" />
          {trip.memberCount} {trip.memberCount === 1 ? "persona" : "personas"}
        </Badge>
      </div>

      <Card className="mt-8 space-y-4 p-5 text-center">
        <p className="text-sm text-text-secondary">
          Te invitaron a este viaje en BarPass.
        </p>
        <a
          href={deepLink}
          className="block w-full rounded-full bg-amber-brand px-6 py-3 text-center text-sm font-bold text-black transition hover:brightness-110"
        >
          Abrir en BarPass
        </a>
        <p className="text-xs text-text-tertiary">
          ¿No tienes la app? Muy pronto en el App Store.
        </p>
      </Card>
    </div>
  );
}
