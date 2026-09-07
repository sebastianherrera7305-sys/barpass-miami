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
export function groundPlanBlock(jsonText: string, shortlist: Venue[]): string {
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

  const plan = parsed as { stops: Array<Record<string, unknown>> };
  plan.stops = plan.stops.map((stop) => {
    const id = typeof stop.venueId === "string" ? stop.venueId : "";
    const slug = typeof stop.venueSlug === "string" ? stop.venueSlug.toLowerCase() : "";
    const name = typeof stop.venueName === "string" ? stop.venueName.toLowerCase() : "";
    const match = byId.get(id) ?? bySlug.get(slug) ?? bySlug.get(id.toLowerCase()) ?? byName.get(name) ?? byName.get(id.toLowerCase());
    if (!match) return stop;
    return { ...stop, venueId: match.id, venueSlug: match.slug, venueName: match.name };
  });
  return JSON.stringify(plan, null, 2);
}

/** Which language the user is writing in — for a hard, recency-weighted reply
 * instruction. Accented characters and a few unambiguous Spanish words are
 * enough; anything else is treated as English. */
export function detectUserLanguage(text: string): "es" | "en" {
  const t = text.toLowerCase();
  if (/[¿¡ñáéíóú]/.test(t)) return "es";
  const es = (t.match(/\b(que|para|donde|dónde|con|una|esta|hoy|noche|quiero|somos|algo|dame|busco|cerca|después|luego|estoy|hay)\b/g) ?? []).length;
  const en = (t.match(/\b(the|and|with|tonight|want|looking|near|after|then|plan|me|for|can|you)\b/g) ?? []).length;
  return es > en ? "es" : "en";
}
