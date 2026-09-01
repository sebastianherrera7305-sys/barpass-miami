"use client";

import { useState } from "react";
import Link from "next/link";
import { motion, AnimatePresence } from "framer-motion";
import { Star } from "lucide-react";
import type maplibregl from "maplibre-gl";
import { formatUSD, formatTime } from "@/lib/utils";
import type { Venue } from "@/types";
import { BaseMap } from "./base-map";
import { VenueMarkers } from "./venue-markers";

/**
 * The live map surface: a real MapLibre map + reconciled venue markers +
 * a floating preview card for the selected venue. Loaded client-only
 * (see venue-map.tsx) so MapLibre never runs during SSR.
 */
export function MapCanvas({
  venues,
  selected,
  onSelect,
}: {
  venues: Venue[];
  selected: Venue | null;
  onSelect: (venue: Venue | null) => void;
}) {
  const [map, setMap] = useState<maplibregl.Map | null>(null);

  return (
    <div className="relative h-full overflow-hidden rounded-[24px] border border-border-subtle">
      <BaseMap onReady={setMap} className="absolute inset-0 h-full w-full" />

      {map && (
        <VenueMarkers
          map={map}
          venues={venues}
          selectedId={selected?.id ?? null}
          onSelect={onSelect}
        />
      )}

      {!map && (
        <div className="absolute inset-0 animate-pulse bg-[radial-gradient(ellipse_at_60%_40%,#12131a_0%,#000_75%)]" />
      )}

      <AnimatePresence>
        {selected && (
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: 20 }}
            className="pointer-events-none absolute bottom-4 left-4 right-4 z-30 md:left-1/2 md:right-auto md:w-96 md:-translate-x-1/2"
          >
            <Link
              href={`/venues/${selected.slug}`}
              className="pointer-events-auto flex items-center justify-between rounded-[18px] border border-border-strong bg-black/95 px-5 py-4 backdrop-blur-xl transition-colors hover:border-amber-brand/50"
            >
              <div className="min-w-0 flex-1">
                <p className="truncate font-bold">
                  {selected.emoji} {selected.name}
                </p>
                <p className="mt-0.5 text-xs text-text-secondary">
                  {selected.neighborhood} · {selected.avgSpend ? `${formatUSD(selected.avgSpend)} avg` : "—"} ·{" "}
                  {formatTime(selected.openTime)}–{formatTime(selected.closeTime)}
                </p>
                <p className="mt-0.5 truncate text-xs text-text-tertiary">
                  {selected.hook}
                </p>
              </div>
              <span className="ml-3 flex shrink-0 items-center gap-1 text-sm font-bold text-amber-brand">
                <Star className="h-3.5 w-3.5 fill-current" />
                {selected.rating}
              </span>
            </Link>
          </motion.div>
        )}
      </AnimatePresence>

      {venues.length === 0 && (
        <p className="pointer-events-none absolute inset-0 grid place-items-center text-sm text-text-tertiary">
          Nothing matches — try adjusting your filters.
        </p>
      )}
    </div>
  );
}
