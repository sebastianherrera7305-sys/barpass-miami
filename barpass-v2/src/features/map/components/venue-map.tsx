"use client";

import { useState } from "react";
import Link from "next/link";
import { Star } from "lucide-react";
import { cn, formatUSD } from "@/lib/utils";
import type { Venue } from "@/types";

const LAYERS = [
  { id: "all", label: "All" },
  { id: "trending", label: "🔥 Trending" },
  { id: "happy_hour", label: "🍹 Happy Hour" },
  { id: "no_cover", label: "🆓 No Cover" },
  { id: "rooftop", label: "🌇 Rooftops" },
  { id: "live", label: "🎺 Live Music" },
] as const;

type LayerId = (typeof LAYERS)[number]["id"];

function matchesLayer(venue: Venue, layer: LayerId): boolean {
  switch (layer) {
    case "all":
      return true;
    case "trending":
      return venue.isTrending;
    case "happy_hour":
      return venue.happyHourUntil !== null;
    case "no_cover":
      return venue.coverMen === null;
    case "rooftop":
      return venue.type === "rooftop";
    case "live":
      return venue.musicGenres.includes("live");
  }
}

/**
 * Live map experience.
 *
 * Current implementation is a schematic map (positioned by lat/lng within
 * Miami's bounding box) so the layer UX ships without a Mapbox token.
 * When NEXT_PUBLIC_MAPBOX_TOKEN lands, the positioning container swaps to
 * react-map-gl — the layer chips and venue popovers stay identical.
 */
export function VenueMap({ venues }: { venues: Venue[] }) {
  const [layer, setLayer] = useState<LayerId>("all");
  const [selected, setSelected] = useState<Venue | null>(null);

  // Miami bounding box for the schematic projection
  const LAT = { min: 25.755, max: 25.83 };
  const LNG = { min: -80.235, max: -80.115 };

  const visible = venues.filter((v) => matchesLayer(v, layer));

  return (
    <div className="relative mx-auto h-[calc(100dvh-160px)] max-w-6xl px-6 pt-6 md:h-[calc(100dvh-120px)]">
      {/* Layer chips */}
      <div className="no-scrollbar mb-4 flex gap-2 overflow-x-auto">
        {LAYERS.map(({ id, label }) => (
          <button
            key={id}
            onClick={() => {
              setLayer(id);
              setSelected(null);
            }}
            className={cn(
              "shrink-0 rounded-full border px-4 py-2 text-[13px] font-semibold transition-colors",
              layer === id
                ? "border-amber-brand bg-amber-brand/12 text-amber-brand"
                : "border-border-subtle bg-surface text-text-secondary hover:text-white",
            )}
          >
            {label}
          </button>
        ))}
      </div>

      {/* Schematic map canvas */}
      <div className="relative h-full overflow-hidden rounded-[24px] border border-border-subtle bg-[radial-gradient(ellipse_at_60%_40%,#12131a_0%,#000_75%)]">
        {/* Water hint (Biscayne Bay on the east) */}
        <div className="absolute inset-y-0 right-0 w-1/5 bg-gradient-to-l from-[#0a1420]/80 to-transparent" />

        {visible.map((venue) => {
          const x =
            ((venue.lng - LNG.min) / (LNG.max - LNG.min)) * 100;
          const y =
            (1 - (venue.lat - LAT.min) / (LAT.max - LAT.min)) * 100;
          return (
            <button
              key={venue.id}
              onClick={() =>
                setSelected(selected?.id === venue.id ? null : venue)
              }
              style={{ left: `${x}%`, top: `${y}%` }}
              className={cn(
                "absolute -translate-x-1/2 -translate-y-1/2 rounded-full border px-2.5 py-1.5 text-lg transition-all",
                selected?.id === venue.id
                  ? "z-20 scale-125 border-amber-brand bg-black shadow-[0_0_20px_rgba(235,184,71,0.4)]"
                  : "z-10 border-border-strong bg-black/80 hover:scale-110",
              )}
              aria-label={venue.name}
            >
              {venue.emoji}
            </button>
          );
        })}

        {/* Selected venue popover */}
        {selected && (
          <Link
            href={`/venues/${selected.slug}`}
            className="absolute bottom-4 left-4 right-4 z-30 flex items-center justify-between rounded-[18px] border border-border-strong bg-black/95 px-5 py-4 backdrop-blur-xl transition-colors hover:border-amber-brand/50 md:left-1/2 md:right-auto md:w-96 md:-translate-x-1/2"
          >
            <div>
              <p className="font-bold">
                {selected.emoji} {selected.name}
              </p>
              <p className="mt-0.5 text-xs text-text-secondary">
                {selected.neighborhood} ·{" "}
                {selected.coverMen === null
                  ? "No cover"
                  : `${formatUSD(selected.coverMen)}+ cover`}{" "}
                · {selected.hook}
              </p>
            </div>
            <span className="flex items-center gap-1 text-sm font-bold text-amber-brand">
              <Star className="h-3.5 w-3.5 fill-current" />
              {selected.rating}
            </span>
          </Link>
        )}

        {/* Empty layer state */}
        {visible.length === 0 && (
          <p className="absolute inset-0 grid place-items-center text-sm text-text-tertiary">
            Nothing on this layer tonight — try another.
          </p>
        )}
      </div>
    </div>
  );
}
