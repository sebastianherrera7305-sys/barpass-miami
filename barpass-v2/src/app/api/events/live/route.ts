import { NextResponse } from "next/server";
import { checkRateLimit } from "@/lib/rate-limit";

/**
 * GET /api/events/live?city=Miami
 * Real, upcoming concerts/nightlife events from the Ticketmaster Discovery
 * API — separate from `events` (BarPass's own venues' events, owned and
 * created by venue owners via POST /api/events). This is external
 * discovery data: what's actually happening in a city, not tied to a
 * BarPass venue at all, shown as its own "This week" row rather than mixed
 * into venue-owned event listings.
 *
 * TICKETMASTER_API_KEY lives server-side only — Discovery API's free tier
 * (5000 calls/day) is a public key by Ticketmaster's own design (it's
 * meant to sit in client apps), but keeping it server-side here still lets
 * us rate-limit and cache without a client ever needing it directly.
 */
const TM_BASE = "https://app.ticketmaster.com/discovery/v2/events.json";

interface LiveEvent {
  id: string;
  name: string;
  date: string | null;
  time: string | null;
  imageUrl: string | null;
  venueName: string | null;
  neighborhood: string | null;
  url: string;
  priceMin: number | null;
  priceMax: number | null;
}

/** Ticketmaster returns ~10 image variants per event at different crops —
 * this picks the widest 16:9 one, which reads best as a horizontal card. */
function pickImage(images: Array<{ url: string; width: number; ratio?: string }> | undefined): string | null {
  if (!images?.length) return null;
  const wide = images.filter((i) => i.ratio === "16_9").sort((a, b) => b.width - a.width);
  return (wide[0] ?? images[0]).url;
}

export async function GET(request: Request) {
  const ip = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "unknown";
  const withinLimit = await checkRateLimit(`events-live:${ip}`, { maxRequests: 30, windowSeconds: 60 });
  if (!withinLimit) {
    return NextResponse.json({ error: "rate_limited" }, { status: 429 });
  }

  if (!process.env.TICKETMASTER_API_KEY) {
    return NextResponse.json({ error: "not_configured" }, { status: 503 });
  }

  const { searchParams } = new URL(request.url);
  const city = searchParams.get("city") ?? "Miami";

  const tmURL = new URL(TM_BASE);
  tmURL.searchParams.set("apikey", process.env.TICKETMASTER_API_KEY);
  tmURL.searchParams.set("city", city);
  tmURL.searchParams.set("countryCode", "US");
  tmURL.searchParams.set("classificationName", "music");
  tmURL.searchParams.set("size", "20");
  tmURL.searchParams.set("sort", "date,asc");

  let upstream: Response;
  try {
    // Revalidate hourly — event listings don't need to be real-time, and
    // this keeps us well inside the free tier's daily call budget no
    // matter how much traffic the app itself gets.
    upstream = await fetch(tmURL.toString(), { next: { revalidate: 3600 } });
  } catch (e) {
    console.error("Ticketmaster fetch failed:", e);
    return NextResponse.json({ error: "upstream_unavailable" }, { status: 502 });
  }

  if (!upstream.ok) {
    console.error(`Ticketmaster call failed: HTTP ${upstream.status}`, await upstream.text().catch(() => ""));
    return NextResponse.json({ error: "upstream_unavailable" }, { status: 502 });
  }

  interface TicketmasterEvent {
    id: string;
    name: string;
    url: string;
    dates?: { start?: { localDate?: string; localTime?: string } };
    images?: Array<{ url: string; width: number; ratio?: string }>;
    priceRanges?: Array<{ min?: number; max?: number }>;
    _embedded?: { venues?: Array<{ name?: string; city?: { name?: string } }> };
  }
  const data = (await upstream.json()) as { _embedded?: { events?: TicketmasterEvent[] } };
  const rawEvents: TicketmasterEvent[] = data._embedded?.events ?? [];

  const events: LiveEvent[] = rawEvents.map((e) => {
    const venue = e._embedded?.venues?.[0];
    const priceRange = e.priceRanges?.[0];
    return {
      id: e.id,
      name: e.name,
      date: e.dates?.start?.localDate ?? null,
      time: e.dates?.start?.localTime ?? null,
      imageUrl: pickImage(e.images),
      venueName: venue?.name ?? null,
      neighborhood: venue?.city?.name ?? null,
      url: e.url,
      priceMin: priceRange?.min ?? null,
      priceMax: priceRange?.max ?? null,
    };
  });

  return NextResponse.json(
    { events },
    { headers: { "Cache-Control": "public, max-age=1800, stale-while-revalidate=3600" } },
  );
}
