/**
 * Lo que le pedimos a Google, y la forma en que vuelve.
 *
 * Separado de `venue-google-patch.ts` a propósito: acá está el CONTRATO con la
 * API (qué campos, con qué nombre, de qué tipo) y allá las DECISIONES sobre qué
 * hacer con lo que llega. Se tocan por razones distintas — un campo nuevo de
 * Google es un cambio acá; una regla nueva de procedencia es un cambio allá.
 */

/**
 * El field mask consolidado, acá y no en el script, porque la máscara y el
 * parser tienen que moverse juntos: pedir un campo que nadie lee es plata
 * tirada, y leer uno que no se pidió es un bug silencioso.
 *
 * El precio de la llamada lo fija el campo más caro — servesBeer/Wine/Cocktails,
 * que son Atmosphere — así que todo lo que esté en Atmosphere o por debajo
 * viaja GRATIS en el mismo request. De ahí que se pidan los amenities: no
 * cuestan nada acá y ahorran una sexta pasada (la de enrich-venues.ts).
 *
 * `editorialSummary` también sería gratis y NO se pide a propósito: no hay
 * columna para el resumen de Google, y la única candidata (`venues.description`)
 * tiene copy escrito por nosotros. Traerlo sólo serviría para que alguien lo
 * pise algún día.
 */
export const REFRESH_FIELD_MASK = [
  "id",
  "displayName",
  "businessStatus",
  "primaryType",
  "types",
  "rating",
  "userRatingCount",
  "websiteUri",
  "nationalPhoneNumber",
  "priceLevel",
  "regularOpeningHours.periods",
  "photos.name",
  "servesBeer",
  "servesWine",
  "servesCocktails",
  "servesVegetarianFood",
  "goodForGroups",
  "goodForWatchingSports",
  "liveMusic",
  "outdoorSeating",
  "reservable",
  "restroom",
  "accessibilityOptions",
] as const;

export interface Period {
  open?: { day: number; hour: number; minute: number };
  close?: { day: number; hour: number; minute: number };
}
export interface DayHours { day: number; open: string; close: string }

/** Only the fields the consolidated mask asks for. */
export interface GooglePlace {
  id?: string;
  displayName?: { text?: string };
  businessStatus?: string;
  primaryType?: string;
  types?: string[];
  rating?: number;
  userRatingCount?: number;
  websiteUri?: string;
  nationalPhoneNumber?: string;
  priceLevel?: string;
  regularOpeningHours?: { periods?: Period[] };
  photos?: { name?: string }[];
  servesBeer?: boolean;
  servesWine?: boolean;
  servesCocktails?: boolean;
  servesVegetarianFood?: boolean;
  goodForGroups?: boolean;
  goodForWatchingSports?: boolean;
  liveMusic?: boolean;
  outdoorSeating?: boolean;
  reservable?: boolean;
  restroom?: boolean;
  accessibilityOptions?: { wheelchairAccessibleEntrance?: boolean };
}

export interface VenueRow {
  id: string;
  name: string;
  city: string | null;
  type: string;
  google_place_id: string | null;
  hours: DayHours[] | null;
  rating: number | null;
  review_count: number | null;
  price_tier: number | null;
  image_url: string | null;
  website: string | null;
  phone: string | null;
  business_status: string | null;
  excluded_reason: string | null;
  field_sources: Record<string, { source?: string } | undefined> | null;
  wheelchair_accessible: boolean | null;
  outdoor_seating: boolean | null;
  good_for_groups: boolean | null;
  good_for_watching_sports: boolean | null;
  has_live_music: boolean | null;
  reservable: boolean | null;
  serves_vegetarian_food: boolean | null;
  restroom: boolean | null;
}

const hhmm = (h: number, m: number) =>
  `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}`;

/**
 * Google periods -> our shape. `day` is the day it OPENS (0 = Sunday); a close
 * earlier than the open runs past midnight, the normal case for nightlife. A
 * period with no close is Google's encoding for "open 24 hours" that day.
 *
 * Duplicated from backfill-venue-hours.ts rather than imported because that
 * file calls main() at module scope — importing it would start a sweep.
 */
export function toWeeklyHours(periods: Period[] | undefined): DayHours[] | null {
  if (!periods?.length) return null;
  const out: DayHours[] = [];
  for (const p of periods) {
    if (!p.open) continue;
    if (!p.close) {
      out.push({ day: p.open.day, open: "00:00", close: "23:59" });
      continue;
    }
    out.push({
      day: p.open.day,
      open: hhmm(p.open.hour, p.open.minute),
      close: hhmm(p.close.hour, p.close.minute),
    });
  }
  return out.length ? out : null;
}

