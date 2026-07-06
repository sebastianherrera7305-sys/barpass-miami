import type { ComponentType } from "react";
import { Car, Navigation, MapPin, AtSign } from "lucide-react";
import { Card } from "@/components/ui/card";
import {
  getDirectionsProviders,
  type DirectionsProviderId,
} from "../services/directions";
import type { Venue } from "@/types";

const PROVIDER_ICON: Record<
  DirectionsProviderId,
  ComponentType<{ className?: string }>
> = {
  uber: Car,
  apple_maps: Navigation,
  google_maps: MapPin,
};

/**
 * "Getting there" — address + one-tap ride/directions actions.
 * Server component: pure links, zero client JS. Uber is the primary action;
 * every link opens the native app when installed, else mobile web.
 */
export function GettingThere({ venue }: { venue: Venue }) {
  const providers = getDirectionsProviders(venue);

  return (
    <Card className="mt-8 p-5">
      <h3 className="flex items-center gap-2 text-sm font-bold">
        <Navigation className="h-4 w-4 text-amber-brand" /> Getting there
      </h3>
      <p className="mt-1 text-sm text-text-secondary">{venue.address}</p>

      <div className="mt-4 flex flex-wrap gap-3">
        {providers.map((provider) => {
          const Icon = PROVIDER_ICON[provider.id];
          return (
            <a
              key={provider.id}
              href={provider.href}
              target="_blank"
              rel="noopener noreferrer"
              className={
                provider.primary
                  ? "inline-flex items-center gap-2 rounded-full bg-gradient-to-r from-amber-brand to-amber-bright px-5 py-2.5 text-sm font-bold text-black transition hover:brightness-110"
                  : "inline-flex items-center gap-2 rounded-full border border-border-subtle bg-surface px-5 py-2.5 text-sm font-semibold text-text-secondary transition hover:text-white"
              }
            >
              <Icon className="h-4 w-4" />
              {provider.label}
            </a>
          );
        })}
      </div>

      {venue.instagramHandle && (
        <a
          href={`https://instagram.com/${venue.instagramHandle}`}
          target="_blank"
          rel="noopener noreferrer"
          className="mt-4 inline-flex items-center gap-1.5 text-xs text-text-tertiary transition-colors hover:text-amber-brand"
        >
          <AtSign className="h-3.5 w-3.5" /> {venue.instagramHandle}
        </a>
      )}
    </Card>
  );
}
