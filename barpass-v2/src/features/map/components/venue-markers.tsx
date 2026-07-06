"use client";

import { useEffect, useRef } from "react";
import maplibregl from "maplibre-gl";
import type { Venue } from "@/types";
import { SELECTED_ZOOM } from "../lib/map-config";

/**
 * Imperatively syncs custom amber venue markers onto a MapLibre map.
 * Renders nothing itself — it reconciles the marker set against `venues`,
 * reflects `selectedId` styling, and flies to the selected venue.
 */
export function VenueMarkers({
  map,
  venues,
  selectedId,
  onSelect,
}: {
  map: maplibregl.Map;
  venues: Venue[];
  selectedId: string | null;
  onSelect: (venue: Venue) => void;
}) {
  const markersRef = useRef<Map<string, maplibregl.Marker>>(new Map());
  const onSelectRef = useRef(onSelect);
  useEffect(() => {
    onSelectRef.current = onSelect;
  });

  // Reconcile markers with the current (filtered) venue set.
  useEffect(() => {
    const markers = markersRef.current;
    const seen = new Set<string>();

    for (const venue of venues) {
      seen.add(venue.id);
      if (!markers.has(venue.id)) {
        const el = document.createElement("button");
        el.className = "bp-marker";
        el.setAttribute("aria-label", venue.name);
        el.textContent = venue.emoji;
        el.addEventListener("click", (e) => {
          e.stopPropagation();
          onSelectRef.current(venue);
        });
        const marker = new maplibregl.Marker({ element: el })
          .setLngLat([venue.lng, venue.lat])
          .addTo(map);
        markers.set(venue.id, marker);
      }
    }

    for (const [id, marker] of markers) {
      if (!seen.has(id)) {
        marker.remove();
        markers.delete(id);
      }
    }
  }, [map, venues]);

  // Reflect selection styling.
  useEffect(() => {
    for (const [id, marker] of markersRef.current) {
      marker.getElement().classList.toggle("bp-marker--active", id === selectedId);
    }
  }, [selectedId, venues]);

  // Fly to the selected venue.
  useEffect(() => {
    if (!selectedId) return;
    const venue = venues.find((v) => v.id === selectedId);
    if (!venue) return;
    map.flyTo({
      center: [venue.lng, venue.lat],
      zoom: Math.max(map.getZoom(), SELECTED_ZOOM),
      duration: 900,
      essential: true,
    });
  }, [map, selectedId, venues]);

  // Clean up all markers on unmount.
  useEffect(() => {
    const markers = markersRef.current;
    return () => {
      for (const marker of markers.values()) marker.remove();
      markers.clear();
    };
  }, []);

  return null;
}
