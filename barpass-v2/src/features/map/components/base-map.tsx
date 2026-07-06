"use client";

import { useEffect, useRef } from "react";
import maplibregl from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import {
  MAP_STYLE,
  MIAMI_CENTER,
  MIAMI_MAX_BOUNDS,
  DEFAULT_ZOOM,
} from "../lib/map-config";

/**
 * Thin, library-isolating MapLibre wrapper. The rest of the app never imports
 * maplibre-gl directly — it consumes the ready `Map` instance via `onReady`.
 * This is the single seam to swap map providers behind.
 */
export function BaseMap({
  onReady,
  className,
}: {
  onReady: (map: maplibregl.Map) => void;
  className?: string;
}) {
  const containerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<maplibregl.Map | null>(null);
  const onReadyRef = useRef(onReady);
  useEffect(() => {
    onReadyRef.current = onReady;
  });

  useEffect(() => {
    if (!containerRef.current || mapRef.current) return;

    const map = new maplibregl.Map({
      container: containerRef.current,
      style: MAP_STYLE,
      center: MIAMI_CENTER,
      zoom: DEFAULT_ZOOM,
      maxBounds: MIAMI_MAX_BOUNDS,
      attributionControl: false,
      cooperativeGestures: false,
    });

    map.addControl(
      new maplibregl.AttributionControl({ compact: true }),
      "bottom-left",
    );
    map.addControl(
      new maplibregl.NavigationControl({ showCompass: false }),
      "bottom-right",
    );
    map.addControl(
      new maplibregl.GeolocateControl({
        positionOptions: { enableHighAccuracy: true },
        trackUserLocation: true,
        showUserLocation: true,
      }),
      "bottom-right",
    );

    map.on("load", () => onReadyRef.current(map));
    mapRef.current = map;

    return () => {
      map.remove();
      mapRef.current = null;
    };
  }, []);

  return <div ref={containerRef} className={className} />;
}
