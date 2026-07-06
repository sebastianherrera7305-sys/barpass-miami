/**
 * Map configuration constants.
 *
 * We use MapLibre GL with CARTO's free dark-matter vector style — no access
 * token, no per-load billing, and a dark aesthetic that matches Deep Cosmos.
 * Isolating these here (and the library behind <BaseMap>) means switching to
 * Mapbox later is a one-file change.
 */

/** Free CARTO dark vector style — no token required. */
export const MAP_STYLE =
  "https://basemaps.cartocdn.com/gl/dark-matter-gl-style/style.json";

/** Downtown-ish Miami center, [lng, lat]. */
export const MIAMI_CENTER: [number, number] = [-80.19, 25.785];

export const DEFAULT_ZOOM = 12.2;
export const SELECTED_ZOOM = 14.5;

/** Keep the viewport around greater Miami, [[swLng, swLat], [neLng, neLat]]. */
export const MIAMI_MAX_BOUNDS: [[number, number], [number, number]] = [
  [-80.42, 25.6],
  [-80.05, 25.95],
];
