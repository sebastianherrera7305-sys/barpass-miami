/**
 * Pulls real, current events for a stadium from Ticketmaster Discovery API
 * and upserts them into stadium_events. Never invents an event — only what
 * Ticketmaster actually returns for that venue right now.
 *
 * Usage:
 *   TICKETMASTER_API_KEY=xxx node --env-file=.env.local --import tsx scripts/sync-stadium-events.ts "Hard Rock Stadium" "Miami Gardens"
 */
import { createClient } from "@supabase/supabase-js";
// @ts-expect-error - ws no trae tipos propios
import ws from "ws";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const TM_KEY = process.env.TICKETMASTER_API_KEY;
if (!SUPABASE_URL || !SERVICE_ROLE_KEY || !TM_KEY) {
  console.error("Faltan env vars (Supabase o TICKETMASTER_API_KEY)");
  process.exit(1);
}
const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  realtime: { transport: ws as unknown as typeof WebSocket },
});

async function findVenueId(name: string, city: string): Promise<string | null> {
  const url = `https://app.ticketmaster.com/discovery/v2/venues.json?keyword=${encodeURIComponent(name)}&city=${encodeURIComponent(city)}&apikey=${TM_KEY}`;
  const res = await fetch(url);
  if (!res.ok) {
    console.error("venues lookup falló:", res.status, await res.text());
    return null;
  }
  const data = await res.json();
  const venue = data._embedded?.venues?.[0];
  if (!venue) return null;
  console.log(`Venue real encontrado en Ticketmaster: "${venue.name}" (id=${venue.id})`);
  return venue.id;
}

async function fetchEvents(venueId: string) {
  const url = `https://app.ticketmaster.com/discovery/v2/events.json?venueId=${venueId}&apikey=${TM_KEY}&size=100`;
  const res = await fetch(url);
  if (!res.ok) {
    console.error("events lookup falló:", res.status, await res.text());
    return [];
  }
  const data = await res.json();
  return data._embedded?.events ?? [];
}

async function main() {
  const [stadiumName, city] = process.argv.slice(2);
  if (!stadiumName || !city) {
    console.error("Uso: sync-stadium-events.ts <stadium name> <city>");
    process.exit(1);
  }

  const { data: stadium } = await supabase.from("stadiums").select("id,name").eq("name", stadiumName).single();
  if (!stadium) {
    console.error(`No existe "${stadiumName}" en la tabla stadiums todavía — cargalo primero.`);
    process.exit(1);
  }

  const venueId = await findVenueId(stadiumName, city);
  if (!venueId) {
    console.error(`Ticketmaster no encontró un venue real para "${stadiumName}" en ${city}. No se inventa nada — reintentá con otro nombre/ciudad si el real difiere.`);
    process.exit(1);
  }

  const events = await fetchEvents(venueId);
  console.log(`${events.length} eventos reales encontrados`);

  let upserted = 0;
  for (const event of events) {
    const startsAt = event.dates?.start?.dateTime
      ?? (event.dates?.start?.localDate ? `${event.dates.start.localDate}T${event.dates.start.localTime ?? "19:00:00"}` : null);
    if (!startsAt) continue; // TBD-date events skipped, not guessed

    const image = (event.images ?? []).sort((a: any, b: any) => (b.width ?? 0) - (a.width ?? 0))[0]?.url ?? null;

    const { error } = await supabase.from("stadium_events").upsert(
      {
        stadium_id: stadium.id,
        ticketmaster_event_id: event.id,
        name: event.name,
        starts_at: startsAt,
        ticket_url: event.url ?? null,
        image_url: image,
        synced_at: new Date().toISOString(),
      },
      { onConflict: "ticketmaster_event_id" }
    );
    if (error) {
      console.error(`FALLÓ "${event.name}":`, error.message);
      continue;
    }
    upserted++;
  }

  console.log(`\n${upserted} eventos sincronizados para ${stadium.name}`);
}

main();
