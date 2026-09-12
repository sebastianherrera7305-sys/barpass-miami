/**
 * Pure rules behind extract-drink-menus.ts — no I/O, so they can be unit
 * tested (scripts/drink-menu-rules.test.ts) and the failure modes found in
 * the 2026-09-12 audit stay fixed:
 *
 *   - "10pm-12am"  was written as happy_hour_until "12:00" (noon)
 *   - "8-10"       was written as "10:00" (morning) — the evening assumption
 *                  only covered 1..9
 *   - "9PM-Close"  was written as "21:00" — the START of the window
 *   - "Mon-Fri 3-6 | Sat-Sun 4-7" was written as "19:00" — one number for a
 *                  window that depends on the day
 *   - a price of $6 was "verified" against a page that only said "$60"
 *
 * The contract for every function here: when the input is ambiguous the
 * answer is null / empty, never a best guess. An empty value is a fact; a
 * guessed one is a lie that survives for months (see music_genres, 2026-09-01).
 */

export interface ExtractedDrink {
  name: string;
  price: number;
  category: string;
  note?: string;
}

export interface ExtractedHappyHour {
  days?: string;
  hours?: string;
  deals?: string;
}

export interface Extracted {
  drinks: ExtractedDrink[];
  happy_hour: ExtractedHappyHour | null;
}

export const DRINK_CATEGORIES = ["cocktail", "beer", "wine", "shot", "bottle", "other"] as const;

export const CATEGORY_EMOJI: Record<string, string> = {
  cocktail: "🍸", beer: "🍺", wine: "🍷", shot: "🥃", bottle: "🍾", other: "🥤",
};

/** Sanity bounds for a single drink price in USD. Outside → not a drink price. */
export const MIN_PRICE = 2;
export const MAX_PRICE = 500;

/** Words that mark a link as a menu / drinks / specials page. */
export const MENU_WORDS = /menu|drink|cocktail|beer|wine|happy|bebida|carta|trago|bottle|specials|food/i;
/** Stricter set for link LABELS: "bar" alone matched "St. Pat's Bar & Grill" on every link of the site. */
const LABEL_WORDS = /\bmenus?\b|drinks?\b|cocktails?\b|beers?\b|wines?\b|happy hour|specials?\b|bebidas?\b|carta\b|tragos?\b|bottle/i;
const ASSET_PATH = /\.(pdf|jpe?g|png|webp|gif|svg|css|js|json|xml|ico|woff2?|mp4)$/i;

export function htmlToText(html: string): string {
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<noscript[\s\S]*?<\/noscript>/gi, " ")
    .replace(/<br\s*\/?>|<\/(p|div|li|tr|h\d|section|article)>/gi, "\n")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/g, " ").replace(/&amp;/g, "&").replace(/&#39;|&rsquo;/g, "'").replace(/&quot;/g, '"')
    .replace(/[ \t]+/g, " ").replace(/\n\s*\n+/g, "\n").trim();
}

/**
 * Same-origin <a> links that look like menu pages, best first (max `limit`).
 *
 * A link whose HREF says menu/drink/happy ranks above one whose label does:
 * on 2026-09-12 St. Pat's NYC read as "no priced text" because the first
 * four matches were the homepage, a .css file and "parties"/"events" (label
 * "St. Pat's Bar" matched `bar`), and the real drink-menu and happy-hours
 * links never made the cut. Asset URLs, the page itself and PDF/image menus
 * (out of scope for v1) are skipped.
 */
export function menuLinks(html: string, base: string, limit = 6): string[] {
  const origin = new URL(base).origin;
  const self = base.split("?")[0].replace(/\/$/, "");
  const byHref: string[] = [];
  const byLabel: string[] = [];
  const seen = new Set<string>();
  for (const m of html.matchAll(/<a\s[^>]*?href=["']([^"'#]+)["'][^>]*>([\s\S]{0,160}?)<\/a>/gi)) {
    const href = m[1]; const label = m[2].replace(/<[^>]+>/g, " ");
    const hrefHit = MENU_WORDS.test(href); const labelHit = LABEL_WORDS.test(label);
    if (!hrefHit && !labelHit) continue;
    try {
      const u = new URL(href, base);
      if (u.origin !== origin) continue;
      if (ASSET_PATH.test(u.pathname)) continue;
      const clean = u.toString().split("?")[0];
      // Dedupe on the slash-insensitive form: Astra Miami offered both
      // "/menus/" and "/menus", the same 20k-char page fetched twice, and the
      // model only ever reads the first PROMPT_TEXT_CHARS — so a duplicate
      // silently costs a real menu page its place in the budget.
      const key = clean.replace(/\/$/, "");
      if (key === self) continue;
      if (seen.has(key)) continue;
      seen.add(key);
      (hrefHit ? byHref : byLabel).push(clean);
    } catch { /* bad href */ }
  }
  // Drinks / happy-hour pages first, generic menus next, food last: the
  // model only reads the first PROMPT_TEXT_CHARS, so page order decides what
  // it sees. St. Pat's NYC: food-menu (5k chars) came first and pushed the
  // happy-hours page past the cut.
  const rank = (u: string) => {
    const path = new URL(u).pathname; // never the host: "bar.example" would rank everything first
    return /drink|cocktail|beer|wine|happy|specials|bebida|trago|bottle|bar\b/i.test(path) ? 0
      : /food|kitchen|eat|brunch|dinner|lunch/i.test(path) ? 2 : 1;
  };
  byHref.sort((a, b) => rank(a) - rank(b));
  return [...byHref, ...byLabel].slice(0, limit);
}

/** True when the page text has a "$<n>" anywhere — the cheap pre-filter before paying for a model call. */
export function hasPricedText(text: string): boolean {
  return /\$\s?\d/.test(text);
}

function escapeRe(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/**
 * Does this exact price literally appear in the source text?
 *
 * The model is told to copy prices, but a model can still round, infer or
 * hallucinate. This is the belt-and-braces check that decides whether a row
 * is written at all. It has to be exact: the previous `text.includes("$6")`
 * accepted "$60", "$6.50" and "$16.00", so a wrong price could pass.
 *
 * Accepts, with digit boundaries on both sides:
 *   "$6", "$ 6", "$6.00", "6.00", "$6.50" (for 6.5), "6 dollars"
 *   a bare "6" ONLY when the drink's own name sits within 60 chars before it
 *   (menus like "Sangria 6 / PBR 6" that omit the currency sign).
 */
export function priceAppearsInText(text: string, price: number, drinkName?: string): boolean {
  if (!Number.isFinite(price) || price <= 0) return false;
  const isInt = Number.isInteger(price);
  // Forms with a decimal point are a strong enough price signal on their own;
  // a bare integer is not (it could be a time, a count, an address).
  const decimalForms = isInt ? [`${price}.00`, `${price}.-`] : [price.toFixed(2), String(price)];
  const forms = isInt ? [String(price), ...decimalForms] : decimalForms;
  const alt = forms.map(escapeRe).join("|");
  const decAlt = decimalForms.map(escapeRe).join("|");
  const nb = "(?<![\\d.])";        // not preceded by a digit or a decimal point ("$16" is not "$6")
  const na = "(?!\\d|\\.\\d)";     // not followed by a digit or ".<digit>" ("$6.50" is not "$6")
  const currency = new RegExp(`${nb}(?:\\$\\s?(?:${alt})${na}|(?:${alt})\\s?(?:\\$|dollars|usd)${na}|(?:${decAlt})${na})`, "i");
  if (currency.test(text)) return true;
  if (!drinkName) return false;
  const stem = drinkName.trim().slice(0, 14);
  if (stem.length < 3) return false;
  const near = new RegExp(`${escapeRe(stem)}[^\\n]{0,60}?${nb}(?:${alt})${na}`, "i");
  return near.test(text);
}

/**
 * Normalise what the model returned into rows we are willing to write.
 * Every survivor has a name, a numeric price inside the sanity bounds, a
 * known category, and a price that literally appears in `sourceText`.
 */
export function sanitizeDrinks(raw: unknown, sourceText: string): ExtractedDrink[] {
  if (!Array.isArray(raw)) return [];
  const seen = new Set<string>();
  const out: ExtractedDrink[] = [];
  for (const d of raw as Array<Record<string, unknown>>) {
    if (!d || typeof d !== "object") continue;
    const name = typeof d.name === "string" ? d.name.trim().replace(/\s+/g, " ").slice(0, 60) : "";
    if (name.length < 2) continue;
    const price = Math.round(Number(d.price) * 100) / 100;
    if (!Number.isFinite(price) || price < MIN_PRICE || price > MAX_PRICE) continue;
    const category = String(d.category ?? "other").toLowerCase();
    const cat = (DRINK_CATEGORIES as readonly string[]).includes(category) ? category : "other";
    if (!priceAppearsInText(sourceText, price, name)) continue;
    const key = name.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    const note = typeof d.note === "string" && d.note.trim() ? d.note.trim().slice(0, 80) : undefined;
    out.push({ name, price, category: cat, ...(note ? { note } : {}) });
  }
  return out;
}

/** Cocktails first (they are what people ask "what should I order" about), then the rest in source order. */
export function pickTopDrinks(drinks: ExtractedDrink[], n = 6): Array<{ name: string; price: number; emoji: string }> {
  return [...drinks]
    .sort((a, b) => (a.category === "cocktail" ? 0 : 1) - (b.category === "cocktail" ? 0 : 1))
    .slice(0, n)
    .map((d) => ({ name: d.name, price: d.price, emoji: CATEGORY_EMOJI[d.category] ?? "🥤" }));
}

interface TimeToken { h: number; m: number; ap: "am" | "pm" | null }

function timeTokens(s: string): TimeToken[] {
  const out: TimeToken[] = [];
  for (const m of s.matchAll(/(?<![\d$.])(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?|a\b|p\b)?(?![\d%])/gi)) {
    const h = parseInt(m[1], 10);
    if (h < 0 || h > 24) continue;
    const mm = m[2] ? parseInt(m[2], 10) : 0;
    if (mm > 59) continue;
    const apRaw = (m[3] ?? "").toLowerCase().replace(/\./g, "");
    const ap: TimeToken["ap"] = apRaw.startsWith("a") ? "am" : apRaw.startsWith("p") ? "pm" : null;
    out.push({ h, m: mm, ap });
  }
  return out;
}

/**
 * End of a happy-hour window as "HH:MM" (24h), or null when the text does
 * not state ONE unambiguous clock time.
 *
 *   "4-7pm" → "19:00"      "11am-2pm" → "14:00"     "until 5:30pm" → "17:30"
 *   "10pm-12am" → "00:00"  "8-10" → "22:00"          "open-4pm" → "16:00"
 *   "9PM-Close" → null (ends at close, not a clock time)
 *   "Mon-Fri 3-6 | Sat-Sun 4-7" → null (depends on the day — happy_hour_until
 *   is one column, there is nowhere honest to put two windows)
 *   "3-8pm, 12-8pm" → "20:00" (several windows, but every one ends at 8pm)
 *
 * The evening assumption for a bare "4-7" is deliberate and documented: a
 * happy hour that ends between 1 and 11 with no am/pm anywhere in the text is
 * an evening thing. Anything with an am/pm anywhere is taken literally.
 */
export function happyHourEnd(hours: string | null | undefined): string | null {
  if (!hours) return null;
  let s = hours.toLowerCase()
    .replace(/\bnoon\b/g, "12pm").replace(/\bmidnight\b/g, "12am")
    .replace(/\b\d+\s+days?\s+(a|per)\s+week\b/g, " ")
    .replace(/\b(7|seven)\s+days\b/g, " ")
    .replace(/\s+/g, " ").trim();
  // Anything that ends the window at "close"/"late" has no clock end time.
  if (/(?:-|–|—|to|til{1,2}|until)\s*(?:close|closing|late|cl\b)/.test(s)) return null;
  // The same window printed twice ("3-7PM 3-7PM") is one window.
  s = s.replace(/^(.+?) \1$/, "$1");
  // Several windows are fine only if every one of them ends at the same time.
  const segments = s.split(/[;|,&]|\band\b/).map((x) => x.trim()).filter(Boolean);
  const ends = new Set<string>();
  for (const seg of segments) {
    const tokens = timeTokens(seg);
    if (tokens.length === 0) continue;   // "Mon-Fri" — a day label, not a window
    if (tokens.length > 2) return null;  // two windows glued together — ambiguous
    const end = windowEnd(tokens);
    if (end === null) return null;
    ends.add(end);
  }
  return ends.size === 1 ? [...ends][0] : null;
}

function windowEnd(tokens: TimeToken[]): string | null {
  const last = tokens[tokens.length - 1];
  const anyAp = tokens.some((t) => t.ap !== null);
  let h = last.h;
  if (last.ap === "am") { if (h === 12) h = 0; }
  else if (last.ap === "pm") { if (h < 12) h += 12; }
  else if (anyAp) {
    // "11am-2" → the start says am, the end has none: an end after an am start is pm if smaller.
    const first = tokens[0];
    if (first.ap === "am" && h < first.h) h += 12;
    else if (first.ap === "pm" && h < 12) h += 12;
  } else if (h >= 1 && h <= 11) {
    h += 12; // evening assumption, see doc comment
  }
  if (h === 24) h = 0;
  if (h > 23) return null;
  return `${String(h).padStart(2, "0")}:${String(last.m).padStart(2, "0")}`;
}

/** How much page text the model sees. ~3.5k tokens — cheap, and enough for a home page plus three menu pages. */
export const PROMPT_TEXT_CHARS = 14_000;

/** The instruction we send with the page text. Kept here so the test can pin the "never guess" clauses. */
export function extractionPrompt(venue: { name: string; type: string; city: string }, text: string, maxChars = PROMPT_TEXT_CHARS): string {
  return `You extract drink menu data from a venue's website text. Venue: "${venue.name}" (${venue.type}, ${venue.city}).
Return ONLY JSON: {"drinks":[{"name":"","price":0,"category":"cocktail|beer|wine|shot|bottle|other","note":""}],"happy_hour":{"days":"","hours":"","deals":""}}
RULES:
- Include a drink ONLY if the text prints its price as a number (with $ or clearly a price) next to it, or as a heading directly above the list it belongs to (e.g. "$7 Drafts" followed by "Bud Light", "Yuengling" → each of those is $7). Copy the digits exactly as printed. Never guess, infer, round, average, convert or estimate a price. "Market price", "ask", ranges with no single number → omit the item.
- Only drinks (cocktails, beer, wine, spirits, shots, bottles, non-alcoholic drinks). Never food, cover charges, tickets or table minimums.
- Max 12 drinks: signature cocktails first, then beer/wine. "note" = size/brand detail only if printed.
- happy_hour ONLY if the text states one; otherwise null. "days" and "hours" verbatim as printed (e.g. "Mon-Fri", "4-7pm"). Never fill in a day or hour the text does not state.
- If there are no priced drinks, return exactly {"drinks":[],"happy_hour":null}. An empty answer is correct; an invented item is not.

TEXT:
${text.slice(0, maxChars)}`;
}
