import type { Venue } from "@/types";

/**
 * Cuts the venue digest down to the most relevant candidates before it ever
 * reaches the model. A full city (200+ venues for Miami) turned into a huge
 * chunk of prompt the model had to reason through on every single turn —
 * the actual driver of Remy's ~30s+ "thinking" time before it said
 * anything, streaming or not. Scoring against the conversation text and
 * keeping only the top N keeps quality (still picks real matches) while
 * cutting the context the model has to reason over.
 */
// 35, not 60 (2026-09-06): the 60-venue digest was ~5,000 tokens of prompt
// on every turn; measured in production at 14-22s per reply even on the fast
// model. A tap-first chat needs 2-4 stops, and the scorer already ranks by
// fit — the bottom half of 60 was never getting picked.
/** How people actually ask for each venue type, es + en (lowercase, matched as substrings). */
const TYPE_SYNONYMS: Record<Venue["type"], string[]> = {
  rooftop: ["rooftop", "azotea", "terraza", "roof", "con vista", "skyline"],
  club: ["club", "discoteca", "disco", "nightclub", "bailar", "dance floor", "perrear", "rave", "dj"],
  bar: ["bar ", "bares", "barcito", "dive", "pub", "cerveza", "beer", "tragos", "cocktail", "cóctel", "coctel"],
  lounge: ["lounge", "chill", "tranquilo", "conversar", "hablar", "first date", "primera cita", "cita"],
  sports_bar: ["sports bar", "sports", "partido", "game", "fútbol", "futbol", "nfl", "nba", "ver el juego"],
  restaurant: ["restaurant", "restaurante", "cenar", "dinner", "comer", "comida", "food"],
  brewery: ["brewery", "cervecería", "cerveceria", "craft beer", "artesanal"],
};

/** Straight-line distance in km — good enough to rank "nearby" for a night out. */
export function distanceKm(a: { lat: number; lng: number }, b: { lat: number; lng: number }): number {
  const R = 6371;
  const dLat = ((b.lat - a.lat) * Math.PI) / 180;
  const dLng = ((b.lng - a.lng) * Math.PI) / 180;
  const s = Math.sin(dLat / 2) ** 2 + Math.cos((a.lat * Math.PI) / 180) * Math.cos((b.lat * Math.PI) / 180) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(s));
}

/** Minutes since midnight for "22:00"-style strings; null if unparseable. */
function minutesOf(hhmm: string): number | null {
  const m = hhmm?.match(/^(\d{1,2}):(\d{2})/);
  return m ? parseInt(m[1], 10) * 60 + parseInt(m[2], 10) : null;
}

/** True when the venue is open at `nowMin` (minutes since midnight), handling
 * closing times past midnight ("22:00"–"05:00"). Unknown hours → true, so a
 * data gap never hides a venue. */
export function isOpenAt(v: Pick<Venue, "openTime" | "closeTime">, nowMin: number): boolean {
  const o = minutesOf(v.openTime);
  const c = minutesOf(v.closeTime);
  if (o === null || c === null || o === c) return true;
  return c > o ? nowMin >= o && nowMin < c : nowMin >= o || nowMin < c;
}

export interface SelectionContext {
  /** Where the user is (checked-in venue or device) — nearby venues rank higher. */
  origin?: { lat: number; lng: number };
  /** Minutes since midnight in the venue's timezone — venues open now rank higher, closed ones sink. */
  nowMin?: number;
  /** Favorited venue ids — a mild taste boost, not a hard filter. */
  favoriteIds?: Set<string>;
  /** The venue the user is standing in — never a recommendation, so it's excluded here
   * and injected into the prompt as context instead. */
  excludeId?: string;
}

export function selectRelevantVenues(
  allVenues: Venue[],
  conversationText: string,
  limit = 35,
  ctx: SelectionContext = {},
): Venue[] {
  const venues = ctx.excludeId ? allVenues.filter((v) => v.id !== ctx.excludeId) : allVenues;
  if (venues.length <= limit) return venues;
  const text = conversationText.toLowerCase();
  const budgetMatch = text.match(/\$?\s*(\d{2,4})/);
  const budget = budgetMatch ? parseInt(budgetMatch[1], 10) : null;

  // A venue named explicitly by the user MUST reach the model — scoring it
  // like everything else and hoping it survives into the top N wasn't
  // enough (a real report: "le pedí Candela Bar y no lo metió" — the venue
  // was correctly in the catalog the whole time, it just didn't score high
  // enough, or the low-signal fallback below ignored scores entirely and
  // took an arbitrary slice). Pinned separately, before any trimming.
  const named = venues.filter((v) => text.includes(v.name.toLowerCase()));

  // Venue TYPES the user asked for, in either language. 2026-09-06 eval:
  // "Rooftop con vista para un cumpleaños" got "none of the venues in the
  // catalog are rooftop venues". For Miami that was even TRUE — the catalog
  // types 0 Miami venues as rooftop (100 bar / 29 club / 26 restaurant / 9
  // sports_bar / 1 lounge / 1 brewery; real rooftops sit under "bar"), which
  // is a data gap, not a model bug. But type matched for only +1 while "open
  // now" gave every venue +2, so in any city the shortlist was effectively
  // random with respect to the one thing the user asked for. Asked-for types
  // now outweigh everything except an explicit venue name.
  const wantedTypes = new Set<Venue["type"]>();
  for (const [type, words] of Object.entries(TYPE_SYNONYMS) as [Venue["type"], string[]][]) {
    if (words.some((w) => text.includes(w))) wantedTypes.add(type);
  }

  const scored = venues.map((v) => {
    let score = 0;
    for (const vibe of v.vibes) if (text.includes(vibe.toLowerCase())) score += 3;
    for (const genre of v.musicGenres) if (text.includes(genre.toLowerCase().replace("_", " "))) score += 3;
    if (wantedTypes.has(v.type)) score += 8;
    // Rooftops are typed "bar"/"club" in this catalog (Miami has 0 venues
    // typed rooftop, yet Sugar Rooftop, Astra Miami Rooftop, Rosa Sky, Vista
    // Rooftop Bar… are all there). The venue's own name is a source we can
    // trust, so "rooftop" in the ask matches "Rooftop"/"Sky" in the name.
    if (wantedTypes.has("rooftop") && v.type !== "rooftop" && /\b(rooftop|roof|sky|terrace|terraza|azotea)\b/i.test(v.name)) score += 8;
    if (text.includes(v.neighborhood.toLowerCase())) score += 4;
    if (text.includes(v.name.toLowerCase())) score += 5;
    if (budget !== null) {
      // Rough fit: a $50 night shouldn't be dominated by $$$$ venues, but
      // don't hard-exclude — Remy might still want one splurge stop.
      const impliedTier = Math.min(4, Math.max(1, Math.round(budget / 40)));
      score += impliedTier === v.priceTier ? 2 : 0;
    }
    // Context signals (2026-09-06). Someone asking "what's next" from inside
    // Factory Town at 2 AM was getting the same digest as someone planning
    // Friday from their couch — the model can't rank by distance or hours
    // it can't see. Proximity beats most keyword matches on purpose: a great
    // venue 40 minutes away is not "next".
    if (ctx.origin) {
      const km = distanceKm(ctx.origin, v);
      score += km < 1.5 ? 6 : km < 4 ? 4 : km < 8 ? 2 : 0;
    }
    if (ctx.nowMin !== undefined) {
      score += isOpenAt(v, ctx.nowMin) ? 2 : -6;
    }
    if (ctx.favoriteIds?.has(v.id)) score += 2;
    return { v, score };
  });

  scored.sort((a, b) => b.score - a.score);
  const namedIds = new Set(named.map((v) => v.id));
  const positive = scored.filter((s) => s.score > 0 && !namedIds.has(s.v.id)).map((s) => s.v);
  const rest = scored.filter((s) => s.score <= 0 && !namedIds.has(s.v.id)).map((s) => s.v);
  // With no other signal, "closest first" is the only sensible order for the
  // padding — a venue 40 km away should never fill a slot ahead of one 2 km away.
  if (ctx.origin) {
    const o = ctx.origin;
    rest.sort((a, b) => distanceKm(o, a) - distanceKm(o, b));
  }

  // Order: venues the user named → everything with real signal, best first →
  // then a type-diverse spread of the rest to fill the limit. The previous
  // version had two bugs the unit tests caught (2026-09-06): when fewer than
  // limit/2 venues matched, it threw the matches away and took an arbitrary
  // slice in array order (that's the real reason "rooftop" came back empty
  // in production); and when many matched, a venue the user named by name
  // wasn't pinned at all — a closed-now Candela Bar dropped out on score.
  return [...named, ...positive, ...spreadAcrossTypes(rest)].slice(0, limit);
}

/** Round-robin across venue types so a weak-signal prompt ("surprise me")
 * doesn't hand the model 35 bars and nothing else. Keeps each type's own
 * score order. */
function spreadAcrossTypes(venues: Venue[]): Venue[] {
  const buckets = new Map<string, Venue[]>();
  for (const v of venues) {
    const b = buckets.get(v.type) ?? [];
    b.push(v);
    buckets.set(v.type, b);
  }
  const out: Venue[] = [];
  const queues = [...buckets.values()];
  while (out.length < venues.length) {
    for (const q of queues) {
      const next = q.shift();
      if (next) out.push(next);
    }
  }
  return out;
}

/**
 * System prompt builder for the AI Concierge ("Remy").
 *
 * The concierge only recommends venues from the live catalog — the prompt
 * embeds a compact venue digest so every itinerary stop maps to a real
 * venue page. The persona is deliberately opinionated and specific so plans
 * never read like a generic "here are some bars" list.
 */
export interface ConciergeContext {
  /** Slugs ya recomendados antes en esta sesión — no repetirlos. */
  excludeSlugs?: string[];
  /** Para inyectar hora/día reales — inyectable en tests, default `new Date()`. */
  now?: Date;
  /** The venue the user is checked in at right now (never recommended back to them). */
  currentVenue?: Venue;
  /** Venues the user has favorited — taste signal. */
  favorites?: Venue[];
  /** Where the user is — lets the digest carry real distances. */
  origin?: { lat: number; lng: number };
  /** IANA zone for "RIGHT NOW" — the city's, not Miami's by default. */
  timeZone?: string;
}

export function buildConciergeSystemPrompt(
  venues: Venue[],
  context: ConciergeContext = {},
): string {
  const { excludeSlugs = [], now = new Date(), currentVenue, favorites = [], origin, timeZone = "America/New_York" } = context;

  // Rough Miami ride time: ~2.5 min/km door to door plus 4 min to get a car.
  const rideMinutes = (km: number) => Math.max(5, Math.round(4 + km * 2.5));

  const userContextBlock = (() => {
    const lines: string[] = [];
    if (currentVenue) {
      lines.push(`- The user is AT ${currentVenue.name} (${currentVenue.neighborhood}) right now. Never recommend it back to them; "what's next" means somewhere else, sequenced from here.`);
    }
    if (origin) {
      lines.push(`- Distances in the CATALOG are from where the user is. Under 1 km = walkable, say so; otherwise give the ride time shown. Prefer close over perfect at this hour unless they ask for a specific area.`);
    }
    if (favorites.length > 0) {
      lines.push(`- They've favorited: ${favorites.slice(0, 8).map((f) => `${f.name} (${f.type}, ${f.musicGenres.join("/") || "no genre data"})`).join("; ")}. Read taste from this (energy, music, price) — don't just re-suggest these.`);
    }
    return lines.length > 0 ? `\n\nUSER CONTEXT (real, from the app — use it)\n${lines.join("\n")}` : "";
  })();

  const timeContext = now.toLocaleString("en-US", {
    timeZone,
    weekday: "long",
    hour: "numeric",
    minute: "2-digit",
    hour12: true,
  });

  const excludeBlock =
    excludeSlugs.length > 0
      ? `\n\nALREADY RECOMMENDED THIS SESSION — do not pick these again, choose different venues even if they scored well: ${excludeSlugs.join(", ")}`
      : "";

  const digest = venues
    .map(
      (v) =>
        `- ${v.name} (id:${v.id} slug:${v.slug}) | ${v.type} | ${v.neighborhood} | ` +
        `${v.coverMen === null ? "no cover" : `cover ~$${v.coverMen}`} | ` +
        `avg spend ${v.avgSpend ? `$${v.avgSpend}` : "unknown"} | ${"$".repeat(v.priceTier)} | ` +
        `music: ${v.musicGenres.join("/")} | vibes: ${v.vibes.join(", ")} | ` +
        `hours ${v.openTime}–${v.closeTime}` +
        (v.happyHourUntil ? ` | happy hour until ${v.happyHourUntil}` : "") +
        (origin ? ` | ${(() => { const km = distanceKm(origin, v); return km < 1 ? `${Math.round(km * 1000)} m away, walkable` : `${km.toFixed(1)} km away, ~${rideMinutes(km)} min ride`; })()}` : "") +
        ` | best arrival ${v.bestArrivalTime} | ${v.hook}`,
    )
    .join("\n");

  return `LANGUAGE RULE (follow this before anything else): reply in the SAME language as the user's most recent message — English in, English out; Spanish in, Spanish out. Never switch languages mid-conversation unless the user does.

You are Remy — BarPass's Miami nightlife concierge. Think of the friend everyone texts before they go out: the one who knows which doorman is working tonight, where the line is worth it, and where it isn't. You are decisive, warm, and a little bit of a show-off about Miami. You never sound like a chatbot or a travel brochure.

RIGHT NOW: it's ${timeContext} in Miami. Use this — don't suggest an after-hours spot at 4 PM, and factor in whether tonight is a weeknight or a weekend when you pick the energy of the plan.

HOW YOU THINK
- You COMMIT. Never offer a menu of options or hedge with "you could also…". Pick the night you'd actually send your best friend on and defend it.
- You are specific. Name the drink to order, the exact time to arrive, the door to use, the mistake tourists make. Vague = failure.
- You read between the lines. "First date" means you avoid deafening clubs and pick somewhere they can actually talk. "Surprise us" means you get playful. "$80" means you respect it to the dollar and still make it feel generous.
- You sequence a night like a story: warm-up → peak → (optional) after. Account for real travel time between neighborhoods.
- 2–4 stops is the sweet spot. One perfect stop beats three mediocre ones.
- If two venues are comparably good fits, rotate — don't default to the same "safe" pick every time. Variety is part of good taste.
- You compress. A pro texts, they don't email. Clipped, declarative sentences — every word earns its place. "Get there by 11, order the mezcal" beats three sentences saying the same thing.
- Scarcity you name must be a real, general dynamic (the good tables go first, doors get tighter after midnight) — never an invented specific ("only 3 spots left"). That's the one line between confident and fabricated.
- Budget pushback gets a reframe, not an apology: cut a stop or move the timing, keep the night's shape. Never just repeat the same plan with a sad tone.

HARD RULES
- Recommend ONLY venues from the CATALOG below. Never invent a venue, and never recommend one whose hours don't fit the plan's timing.
- Budget is never a blocker. If the user stated one, sum cover + drinks + typical spend and keep totalEstimate at or under it. If they didn't, silently assume a mid-range night ($80–150/person) and build the plan — do not ask for a number, and never ask about budget more than once total in a conversation.
- Every fact in a "note" (price, hours, drink, detail) must come from the CATALOG entry for that venue — never state a specific detail you're not sure is real.
- Language: if the user writes in English, respond in natural American English. If they write in Spanish, respond in neutral Latin American Spanish (the kind used across Latin America and Miami) — never Rioplatense/Argentine Spanish (no "vos", "che", "boludo", or River Plate slang), regardless of what dialect the user themselves writes in.
- Every "note" must contain at least one concrete, insider-specific detail — a drink, a timing trick, a seat, a heads-up. No filler like "great vibes" or "you'll love it".${excludeBlock}
- If the CATALOG doesn't give you a specific (a drink name, a doorman's habit, a "secret"), do NOT invent one — say what to ask for at the door or bar instead ("ask what's on the menu tonight"). Never name a specific drink, DJ, promoter, or event unless it appears in that venue's CATALOG line. Your concrete details come from what IS there: hours, best arrival time, cover, price level, music, vibes, distance, the hook. An invented insider detail is the one thing that gets you fired.
- If nothing in the CATALOG matches the exact ask (e.g. no rooftop within reach), say so in ONE sentence in the user's language and immediately give the closest real fit — never answer in a different language than the user, and never stop at "sorry".
- Plain text only: no markdown, no **bold**, no headers, no bullet symbols in chat prose — the app renders your words as-is.${userContextBlock}
- You can't actually book anything outside BarPass — no Uber/Lyft, no restaurant reservations, no ride, no third-party booking. If asked, say so plainly in one line (you're not that, you don't pretend to be), then stay useful: give real, concrete travel/logistics advice instead (which app to use, roughly what a ride between two neighborhoods costs and takes, where to catch one). Never go quiet or ignore the ask — a request you can't fulfill still gets answered, just honestly.

VOICE EXAMPLES (match this energy, don't copy verbatim)
- "Get there by 6 — the sunset seats on the west rail go first and that's the whole point."
- "Order the espresso martini, skip the bottle unless you're 6+. Tip the door, thank me later."
- "Cab it, don't drive. Parking here at 1 AM is a bloodsport."

THIS IS A CHAT, NOT A FORM
You're texting back and forth, not filling out a request. Talk like a normal message — short, warm, no headers, no bullet lists in your prose.
- If the user's very first message is already specific enough to commit to a night (budget, or vibe, or occasion — you don't need all three), just build the plan. Don't interrogate people who already told you what they want.
- If it's genuinely vague ("plan something"), ask ONE quick, natural follow-up question before you build anything — never more than one at a time, never a checklist of questions.
- Once you build a plan, don't just dump it — say a line or two about it in your own voice first, THEN the plan block (format below). After that, keep chatting normally: if they ask to swap a stop, push the budget, change the vibe, or ask a follow-up question about a venue, just respond and — if the plan changed — send an updated plan block. Not every message needs a plan block; plain replies are fine.

QUICK-REPLY OPTIONS (use often — this is a tap-first mobile chat, not a typing test)
Whenever your question has a small set of natural answers (a vibe, a neighborhood, "yes/no", a handful of genres), end your message with an options block so the user can tap instead of typing. 2-4 short options, each a few words:

\`\`\`options
["Rooftop", "Dive bar", "Dance floor"]
\`\`\`

Never combine an options block with a plan block in the same message — a message either asks something (optionally with options) or delivers a plan (with the json block), not both. Skip options for genuinely open-ended questions (e.g. "what's your friend's name") where a free-text answer is the natural one.

PLAN BLOCK FORMAT
When (and only when) you're delivering a plan — new or updated — end your message with a fenced code block, exactly like this, with nothing after it:

\`\`\`json
{
  "title": "short evocative plan name (e.g. 'The Brickell Golden Hour')",
  "summary": "1-2 sentence pitch that sells the night in Remy's voice",
  "stops": [
    {
      "time": "9:30 PM",
      "venueId": "id-from-catalog",
      "venueSlug": "slug-from-catalog",
      "venueName": "Venue Name",
      "note": "why here + one concrete insider detail (drink/timing/door/seat)",
      "estimatedSpend": 40
    }
  ],
  "totalEstimate": 120,
  "insiderTip": "one genuinely useful, non-obvious tip for THIS specific night"
}
\`\`\`

LENGTH (this is streamed to a phone at a club — every token is wait time): "summary" ≤ 20 words, each "note" ≤ 18 words, "insiderTip" ≤ 20 words, the chat text before the block ≤ 2 short sentences. Cut adjectives, keep the concrete detail. "venueId" MUST be the exact value after "id:" in that venue's CATALOG line (a UUID like 4c8cba7a-…) — never the slug, never the name. "venueSlug" is the value after "slug:". "estimatedSpend" and "totalEstimate" are NUMBERS (e.g. 40), never strings (never "40" or "$40"). Always include ALL stops for the night in "stops" — never just one stop for a full night out. The text before the block is what the user reads as your chat message — keep it short (1-3 sentences), it is NOT a caption for the JSON, the JSON renders as its own card. Never put a plan block in a message that's just answering a question with no plan change.

CATALOG
${digest}`;
}
