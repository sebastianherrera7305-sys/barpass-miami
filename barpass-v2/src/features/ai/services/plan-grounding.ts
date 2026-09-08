import type { Venue } from "@/types";

/**
 * Perplexity-style "verify the citation": the model's plan block is untrusted,
 * and a 20B model will occasionally put a slug or a name where the UUID goes,
 * or drift a name by a word. Every stop is re-anchored to the shortlist the
 * model was actually shown — by id, then slug, then case-insensitive name —
 * so venueId/venueSlug/venueName always describe ONE real venue. A stop that
 * matches nothing is left untouched (the clients already fall back by name)
 * rather than dropped: silently shrinking a plan is worse than one soft stop.
 *
 * Returns the block re-serialized (pretty, 2 spaces) or the original text when
 * it isn't valid JSON — never throws, never blocks the stream.
 */
export function groundPlanBlock(jsonText: string, shortlist: Venue[]): string | null {
  let parsed: unknown;
  try {
    parsed = JSON.parse(jsonText);
  } catch {
    return jsonText;
  }
  if (!parsed || typeof parsed !== "object" || !Array.isArray((parsed as { stops?: unknown }).stops)) return jsonText;

  const byId = new Map(shortlist.map((v) => [v.id, v]));
  const bySlug = new Map(shortlist.map((v) => [v.slug.toLowerCase(), v]));
  const byName = new Map(shortlist.map((v) => [v.name.toLowerCase(), v]));

  const plan = parsed as Record<string, unknown> & { stops: Array<Record<string, unknown>> };
  const before = plan.stops.length;
  // Same plain-text rule as the prose: the card renders raw strings.
  const unbold = (x: unknown) => (typeof x === "string" ? x.replace(/\*\*/g, "") : x);
  for (const k of ["title", "summary", "insiderTip"]) plan[k] = unbold(plan[k]);
  const grounded: Array<Record<string, unknown>> = [];
  for (const raw of plan.stops) {
    const stop: Record<string, unknown> = { ...raw, note: unbold(raw.note), venueName: unbold(raw.venueName) };
    const id = typeof stop.venueId === "string" ? stop.venueId : "";
    const slug = typeof stop.venueSlug === "string" ? stop.venueSlug.toLowerCase() : "";
    const name = typeof stop.venueName === "string" ? stop.venueName.toLowerCase() : "";
    const match = byId.get(id) ?? bySlug.get(slug) ?? bySlug.get(id.toLowerCase()) ?? byName.get(name) ?? byName.get(id.toLowerCase());
    if (!match) continue;
    grounded.push({ ...stop, venueId: match.id, venueSlug: match.slug, venueName: match.name });
  }
  plan.stops = grounded;
  // A stop that matches nothing in the shortlist is an invented venue —
  // 2026-09-08 production run put "South Beach Strip" in a plan, a place
  // that doesn't exist, which the app would render as a tappable card that
  // goes nowhere. Dropped rather than shown. If nothing survives, the caller
  // drops the whole block: better a plain answer than a fabricated itinerary.
  if (plan.stops.length === 0) return null;
  if (plan.stops.length !== before) {
    const spend = plan.stops.reduce((sum, s) => sum + (typeof s.estimatedSpend === "number" ? s.estimatedSpend : 0), 0);
    if (spend > 0) plan.totalEstimate = spend;
  }
  return JSON.stringify(plan, null, 2);
}

/** Which language the user is writing in — for a hard, recency-weighted reply
 * instruction. Returns null when there's genuinely no signal, so the caller
 * can stay quiet instead of forcing a language: a tie used to mean English,
 * which answered "llevame a e11even" in English (2026-09-08). */
export function detectUserLanguage(text: string): "es" | "en" | null {
  const t = text.toLowerCase();
  if (/[¿¡ñáéíóú]/.test(t)) return "es";
  const es = (t.match(/\b(que|qué|para|donde|dónde|con|una|uno|unos|esta|este|hoy|noche|noches|quiero|quisiera|queremos|somos|algo|dame|busco|buscamos|cerca|después|luego|estoy|estamos|hay|vamos|voy|ir|llevame|llévame|ponme|recomienda|recomiendame|mejor|lugar|lugares|tragos|trago|barato|caro|amigos|novia|cumpleaños|salir|bailar|comer|cena|gracias|porfa|por favor|el|los|las|del|al|mi|tu|su|es|son|muy|más|pero|sin|sobre|entre|donde sea)\b/g) ?? []).length;
  const en = (t.match(/\b(the|and|with|tonight|want|wanna|looking|near|nearby|after|then|plan|for|can|you|your|what|where|how|good|best|place|places|drinks|drink|cheap|expensive|friends|birthday|go|going|take|show|give|recommend|please|thanks|is|are|an|of|to|my)\b/g) ?? []).length;
  if (es === en) return null;
  return es > en ? "es" : "en";
}
