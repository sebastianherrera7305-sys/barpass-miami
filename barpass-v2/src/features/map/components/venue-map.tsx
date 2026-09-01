"use client";

import { useState, useMemo } from "react";
import dynamic from "next/dynamic";
import Link from "next/link";
import { motion } from "framer-motion";
import { Star, Search, MapIcon, List, X } from "lucide-react";
import { cn, formatUSD, formatTime } from "@/lib/utils";
import type { Venue } from "@/types";

/**
 * The real map is loaded client-only — MapLibre touches `window` and is a
 * heavy dependency, so it stays out of SSR and the initial JS bundle.
 */
const MapCanvas = dynamic(
  () => import("./map-canvas").then((m) => m.MapCanvas),
  {
    ssr: false,
    loading: () => (
      <div className="h-full animate-pulse rounded-[24px] border border-border-subtle bg-[radial-gradient(ellipse_at_60%_40%,#12131a_0%,#000_75%)]" />
    ),
  },
);

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
    case "all": return true;
    case "trending": return venue.isTrending;
    case "happy_hour": return venue.happyHourUntil !== null;
    case "no_cover": return venue.coverMen === null;
    case "rooftop": return venue.type === "rooftop";
    case "live": return venue.musicGenres.includes("live");
  }
}

export function VenueMap({ venues }: { venues: Venue[] }) {
  const [viewMode, setViewMode] = useState<"map" | "list">("map");
  const [layer, setLayer] = useState<LayerId>("all");
  const [search, setSearch] = useState("");
  const [neighborhoodFilter, setNeighborhoodFilter] = useState<string | null>(null);
  const [selected, setSelected] = useState<Venue | null>(null);

  const neighborhoods = useMemo(
    () => [...new Set(venues.map((v) => v.neighborhood))],
    [venues],
  );

  const visible = useMemo(
    () =>
      venues.filter((v) => {
        if (!matchesLayer(v, layer)) return false;
        if (neighborhoodFilter && v.neighborhood !== neighborhoodFilter) return false;
        if (search) {
          const q = search.toLowerCase();
          return (
            v.name.toLowerCase().includes(q) ||
            v.neighborhood.toLowerCase().includes(q) ||
            v.type.toLowerCase().includes(q) ||
            v.hook.toLowerCase().includes(q)
          );
        }
        return true;
      }),
    [venues, layer, neighborhoodFilter, search],
  );

  return (
    <div className="mx-auto h-[calc(100dvh-160px)] max-w-6xl px-6 pt-6 md:h-[calc(100dvh-120px)]">
      <div className="mb-3 flex items-center gap-3">
        <div className="relative flex-1">
          <Search className="absolute left-4 top-1/2 h-4 w-4 -translate-y-1/2 text-text-tertiary" />
          <input
            type="text"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search venues, neighborhoods…"
            className="w-full rounded-full border border-border-subtle bg-surface py-2.5 pl-11 pr-10 text-[14px] placeholder:text-text-tertiary focus:border-amber-brand/50 focus:outline-none"
          />
          {search && (
            <button
              onClick={() => setSearch("")}
              className="absolute right-4 top-1/2 -translate-y-1/2 text-text-tertiary hover:text-white"
            >
              <X className="h-4 w-4" />
            </button>
          )}
        </div>
        <div className="flex shrink-0 rounded-full border border-border-subtle bg-surface">
          <button
            onClick={() => setViewMode("map")}
            className={cn(
              "rounded-full p-2.5 transition-colors",
              viewMode === "map"
                ? "bg-amber-brand/12 text-amber-brand"
                : "text-text-tertiary hover:text-white",
            )}
            aria-label="Map view"
          >
            <MapIcon className="h-4 w-4" />
          </button>
          <button
            onClick={() => setViewMode("list")}
            className={cn(
              "rounded-full p-2.5 transition-colors",
              viewMode === "list"
                ? "bg-amber-brand/12 text-amber-brand"
                : "text-text-tertiary hover:text-white",
            )}
            aria-label="List view"
          >
            <List className="h-4 w-4" />
          </button>
        </div>
      </div>

      <div className="no-scrollbar mb-3 flex gap-2 overflow-x-auto">
        <select
          value={neighborhoodFilter ?? ""}
          onChange={(e) => setNeighborhoodFilter(e.target.value || null)}
          className="shrink-0 rounded-full border border-border-subtle bg-surface px-4 py-2 text-[13px] text-text-secondary focus:outline-none"
        >
          <option value="">All neighborhoods</option>
          {neighborhoods.map((n) => (
            <option key={n} value={n}>
              {n}
            </option>
          ))}
        </select>
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

      <p className="mb-3 text-xs text-text-tertiary">
        {visible.length} venue{visible.length !== 1 ? "s" : ""}
        {search && <> · matching &ldquo;{search}&rdquo;</>}
      </p>

      <div className="relative h-full overflow-hidden rounded-[24px]">
        {viewMode === "map" ? (
          <MapCanvas venues={visible} selected={selected} onSelect={setSelected} />
        ) : (
          <div className="h-full overflow-y-auto rounded-[24px] border border-border-subtle bg-surface/50">
            {visible.length === 0 ? (
              <p className="grid h-full place-items-center text-sm text-text-tertiary">
                Nothing matches — try adjusting your filters.
              </p>
            ) : (
              <div className="divide-y divide-border-subtle">
                {visible.map((venue, i) => (
                  <motion.div
                    key={venue.id}
                    initial={{ opacity: 0, x: -12 }}
                    animate={{ opacity: 1, x: 0 }}
                    transition={{ delay: 0.04 * i, duration: 0.25 }}
                  >
                    <Link
                      href={`/venues/${venue.slug}`}
                      className="flex items-center gap-4 px-5 py-4 transition-colors hover:bg-surface-raised"
                    >
                      <span className="grid h-12 w-12 shrink-0 place-items-center rounded-full bg-surface text-2xl">
                        {venue.emoji}
                      </span>
                      <div className="min-w-0 flex-1">
                        <p className="font-bold">{venue.name}</p>
                        <p className="mt-0.5 text-xs text-text-secondary">
                          {venue.neighborhood} ·{" "}
                          {venue.type.replace("_", " ")}
                        </p>
                        <div className="mt-1 flex flex-wrap items-center gap-x-2 gap-y-0.5 text-xs text-text-tertiary">
                          <span className="flex items-center gap-0.5 text-amber-brand">
                            <Star className="h-3 w-3 fill-current" />
                            {venue.rating}
                          </span>
                          <span>{venue.avgSpend ? `${formatUSD(venue.avgSpend)} avg` : "—"}</span>
                          {venue.coverMen === null && <span>No cover</span>}
                          {venue.isTrending && <span>🔥 Trending</span>}
                          {venue.happyHourUntil && (
                            <span>🍹 HH until {formatTime(venue.happyHourUntil)}</span>
                          )}
                        </div>
                      </div>
                    </Link>
                  </motion.div>
                ))}
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
