/**
 * Pure rules behind extract-door-facts.ts — what a venue publishes about its
 * DOOR: cover, dress code, age policy. No I/O, so every rule is unit tested
 * (scripts/door-facts-rules.test.ts).
 *
 * The contract, same as drink-menu-rules.ts: when the page does not say it,
 * the answer is null. Never a best guess. A cover invented here makes someone
 * show up with exactly enough money and not get in; a dress code invented here
 * makes someone change clothes for a rule that does not exist.
 *
 * The two failure modes these rules exist to stop:
 *   - "cover band", "we've got you covered", "covered patio" are not covers.
 *   - "$14 burger" is a food price; a number is only a cover when the page
 *     puts a door word next to it.
 * and one subtler one: "ladies free before 11" is NOT cover_women = 0. It is
 * free under a condition. Detected and reported, never written (the caller
 * checks `conditional`).
 */

/** One door fact plus the literal page sentence that justifies it. */
export interface CoverFinding {
  men: number | null;
  women: number | null;
  /** The amount only holds under a condition (before 11, with RSVP, on the list…). Do not write it. */
  conditional: boolean;
  /** The sentence exactly as it appears in the page text. */
  evidence: string;
}
export interface TextFinding { value: string; evidence: string }
export type AgeValue = "18+" | "21+" | "mixed";
export interface AgeFinding { value: AgeValue; evidence: string }

/** A cover above this is a bottle-service minimum or a festival ticket, not a door price. */
export const MAX_COVER = 200;

const DOOR_WORD = /\b(?:cover|admission|entry\s*fee|entrance\s*fee|door\s*(?:charge|fee|price)|entrada)\b/i;

/** "cover" that is not a door charge. Any of these kills the whole line. */
const COVER_FALSE_POSITIVE =
  /\bcover(?:s|ed|ing)?\b[^.\n]{0,24}\b(?:band|bands|song|songs|tune|tunes|hit|hits|tribute|artist|setlist|set list|classics)\b|\b(?:band|bands|dj|duo|trio|group)\b[^.\n]{0,24}\bcover(?:s|ing)?\b|\bcovered?\s+(?:patio|deck|parking|terrace|porch|area|seating|bar)\b|\bcoverage\b|\bcover\s+letter\b|\b(?:got|have|has|hav)\s+(?:you|u|ya)\s+covered\b|\bcover(?:s|ed)?\s+(?:the|your|our|us|all)\b/i;

/** The amount is conditional on something the page also states. */
const CONDITIONAL =
  /\b(?:before|after|until|til|till|b4|past|by)\s+\d|\b(?:rsvp|guest\s*list|guestlist|on\s+the\s+list|with\s+(?:a|an|your)\b|w\/|early\s*bird|ticket|presale|pre-sale|promo|birthday|student\s+id|industry\s+night)\b/i;

const MEN = /\b(?:men|man|guys|gentlemen|gents|dudes|males?|fellas|bros)\b/i;
const WOMEN = /\b(?:ladies|lady|women|woman|girls|females?|gals)\b/i;
const FREE = /\b(?:free|no\s+cover|complimentary|comp'?d?)\b/i;

const NO_COVER =
  /\b(?:no|never\s+(?:a|any)|zero|without\s+a)\s+(?:cover|admission|entry|door)\s*(?:charge|fee)?\b|\b(?:admission|entry|entrance)\s+is\s+free\b|\bfree\s+(?:admission|entry|entrance)\b/i;

/** "$10 cover" / "cover $10" / "cover charge: $10" / "$10 at the door". */
/** A cover is a whole number of dollars. "$12.50" is a drink, not a door price — the
 *  lookahead is what keeps "$12.50" from being read as $12 (drink-menu-rules hit the
 *  same trap with "$6" matching "$60"). */
const AMT = "\\$\\s?(\\d{1,3})(?:\\.00)?(?!\\d|\\.\\d)";
const AMOUNT_BEFORE = new RegExp(`${AMT}[^.\\n$]{0,20}?(?:cover|admission|entry|entrance|door)\\b`, "i");
const AMOUNT_AFTER = new RegExp(`\\b(?:cover(?:\\s*charge)?|admission|entry\\s*fee|entrance\\s*fee|door\\s*(?:charge|fee|price))\\b[^.\\n$]{0,20}?${AMT}`, "i");

/** Split page text into short, self-contained sentences — the unit of evidence. */
export function candidateLines(text: string, keyword: RegExp, maxLen = 220): string[] {
  return text
    .split(/\n|(?<=[.!?])\s+|\s*[|•··]\s*/)
    .map((l) => l.replace(/\s+/g, " ").trim())
    .filter((l) => l.length > 0 && l.length <= maxLen && keyword.test(l));
}

function dollars(raw: string | undefined): number | null {
  if (raw === undefined) return null;
  const n = Number(raw);
  return Number.isInteger(n) && n >= 0 && n <= MAX_COVER ? n : null;
}

/** Gendered amounts in either order: "men $20, ladies free" / "$20 men". */
function genderedCover(line: string): { men: number | null; women: number | null } {
  let men: number | null = null;
  let women: number | null = null;
  const assign = (who: string, amount: number | null, free: boolean) => {
    const v = free ? 0 : amount;
    if (v === null) return;
    if (MEN.test(who)) men = men ?? v;
    else if (WOMEN.test(who)) women = women ?? v;
  };
  for (const m of line.matchAll(
    /\b(men|man|guys|gentlemen|gents|dudes|males?|fellas|bros|ladies|lady|women|woman|girls|females?|gals)\b\s*(?:pay|are|is|get\s+in)?\s*[:\-–=]?\s*(free|no\s+cover|\$\s?\d{1,3}(?:\.00)?(?!\d|\.\d))/gi,
  )) assign(m[1], dollars(/\d{1,3}/.exec(m[2])?.[0]), FREE.test(m[2]));
  for (const m of line.matchAll(
    /\$\s?(\d{1,3})(?:\.00)?(?!\d|\.\d)\s*(?:for\s+|cover\s+for\s+)?\b(men|man|guys|gentlemen|gents|dudes|males?|fellas|bros|ladies|lady|women|woman|girls|females?|gals)\b/gi,
  )) assign(m[2], dollars(m[1]), false);
  for (const m of line.matchAll(
    /\b(?:free|no\s+cover)\s+(?:for\s+|entry\s+for\s+|admission\s+for\s+)?\b(men|guys|gentlemen|ladies|women|girls|females?|gals)\b/gi,
  )) assign(m[1], 0, true);
  return { men, women };
}

/**
 * The cover this page states, or null when it states none.
 * An ungendered amount applies to everyone, so it fills both columns.
 */
export function detectCover(text: string): CoverFinding | null {
  for (const line of candidateLines(text, DOOR_WORD)) {
    if (COVER_FALSE_POSITIVE.test(line)) continue;
    const conditional = CONDITIONAL.test(line);
    const g = genderedCover(line);
    if (g.men !== null || g.women !== null) return { ...g, conditional, evidence: line };
    if (NO_COVER.test(line)) return { men: 0, women: 0, conditional, evidence: line };
    const amount = dollars(AMOUNT_BEFORE.exec(line)?.[1] ?? AMOUNT_AFTER.exec(line)?.[1]);
    if (amount !== null) return { men: amount, women: amount, conditional, evidence: line };
  }
  return null;
}

const DRESS_WORD =
  /\bdress\s*code\b|\bdress\s+to\s+impress\b|\bno\s+(?:hats|caps|athletic|sportswear|sneakers|tank\s*tops|shorts|flip\s*[- ]?flops|sandals|baggy|ripped|jerseys|sweatpants|hoodies|work\s+boots|sagging)\b|\bcollared\s+shirts?\b|\bbusiness\s+casual\b|\bsmart\s+casual\b|\bupscale\s+attire\b|\bdressy\b|\bproper\s+attire\b/i;
/** "dressing room", "salad dressing", "dressed in" — the word without the rule. */
const DRESS_FALSE_POSITIVE = /\bdressing\b|\bdressed\b|\bdress\s+(?:shop|store|rental)\b|\bsalad\b/i;
/**
 * A hard rule is self-evident wherever it appears: "no hats", "collared shirts".
 * A soft one is a vibe word that marketing copy also uses. Measured 2026-09-16:
 * American Social Miami's private-events page reads "bring the cheer, unwind,
 * shoot the breeze or dress to impress" — prose, not a door policy. So a soft
 * signal only counts with an enforcement cue in the same sentence, or when the
 * sentence is short enough to BE the rule ("Dress to impress.").
 */
const DRESS_HARD =
  /\bno\s+(?:hats|caps|athletic|sportswear|sneakers|tank\s*tops|shorts|flip\s*[- ]?flops|sandals|baggy|ripped|jerseys|sweatpants|hoodies|work\s+boots|sagging)\b|\bcollared\s+shirts?\b/i;
const DRESS_CUE =
  /\bdress\s*code\b|\battire\b|\bpolicy\b|\brequired\b|\benforced?\b|\bstrictly\b|\bmust\b|\bno\s+exceptions\b|\bplease\b|\bwe\s+ask\b|\bnot\s+permitted\b|\bnot\s+allowed\b/i;
const SOFT_MAX_LEN = 45;
/** The right-hand side of "Dress code: ___" is only the value when it reads like a rule. */
const DRESS_RULEISH =
  /\bno\b|\bcollared\b|\bimpress\b|\bcasual\b|\bformal\b|\bupscale\b|\belegant\b|\bchic\b|\bdressy\b|\battire\b|\bshirts?\b|\bshoes\b|\bcome\s+as\s+you\s+are\b/i;

/**
 * The dress code, in the venue's OWN words (never paraphrased — a rule is
 * repeated to the door guy, so it has to be what the sign says).
 */
export function detectDressCode(text: string): TextFinding | null {
  for (const line of candidateLines(text, DRESS_WORD, 200)) {
    if (DRESS_FALSE_POSITIVE.test(line) && !/\bdress\s*code\b/i.test(line)) continue;
    // "Dress code: smart casual" → keep the right-hand side; a bare heading is not a rule.
    const split = /^(.*?)\bdress\s*code\b\s*[:\-–—]?\s*(.+)$/i.exec(line);
    // "We enforce a business casual dress code on Fridays": the rule is to the LEFT of
    // the words "dress code", so taking the right-hand side would store "on Fridays".
    const ruleIsBefore = split ? DRESS_WORD.test(split[1].replace(/\bdress\s*code\b/gi, " ")) : false;
    const after = ruleIsBefore ? undefined : split?.[2]?.trim();
    // A soft signal alone ("dress to impress") inside a long sentence is copy, not a rule.
    if (!DRESS_HARD.test(line) && !DRESS_CUE.test(line) && line.length > SOFT_MAX_LEN) continue;
    const useAfter = after !== undefined && after.length >= 3 && DRESS_RULEISH.test(after);
    const value = (useAfter ? after : line).replace(/\s+/g, " ").trim();
    if (value.length < 3 || value.length > 160) continue;
    return { value, evidence: line };
  }
  return null;
}

const AGE_WORD = /\b(?:21|18)\s*(?:\+|and\s+(?:over|up|older)|&\s*(?:over|up)|\s*(?:to|and)\s+(?:enter|drink|party))|\bages?\s+(?:21|18)\b|\bmust\s+be\s+(?:21|18)\b|\bover\s+(?:21|18)\b/i;
/** "21 beers on tap", "18 holes", "21 years in business", "18% gratuity". */
const AGE_FALSE_POSITIVE =
  /\b(?:21|18)\s*(?:%|beers?|taps?|holes?|oz|years?\s+(?:in|of)\s+(?:business|experience)|locations?|flavors?|varieties|screens?|tvs?)\b/i;
/**
 * Drink-promo fine print. Measured 2026-09-16: the FIRST hit of the first dry
 * run was Applebee's Gainesville, whose page says "Must be 21+. Void where
 * prohibited. Tax & gratuity excluded." — that is the legal footer of a $6
 * cocktail deal, not a door policy. Applebee's admits everyone. Writing 21+
 * there would have told a 19-year-old they cannot walk into an Applebee's.
 */
const AGE_FINE_PRINT =
  /\bvoid\s+where\s+prohibited\b|\bno\s+purchase\s+necessary\b|\bterms\s+(?:and|&)\s+conditions\b|\bsweepstakes\b|\btax\s*(?:&|and)\s*gratuity\b|\bparticipation\s+may\s+vary\b|\bwhile\s+supplies\s+last\b|\bdrink\s+responsibl|\blegal\s+drinking\s+age\b|\bto\s+(?:consume|purchase|order|buy)\s+(?:alcohol|drinks?)\b/i;
/**
 * An age number is an ENTRY policy only when the same sentence is about
 * getting in. "Must be 21+" on its own is usually about buying a drink —
 * which is the law everywhere and says nothing about this venue's door.
 */
/**
 * An age gate on SELLING, not on entering. Measured 2026-09-16 on Bayside
 * Cigars: "we can only ship cigars and tobacco products to customers aged 21
 * or older" is shipping law, and it would have been written as this venue's
 * door policy.
 */
const COMMERCE_CONTEXT =
  /\bship(?:s|ping|ped)?\b|\bdeliver(?:y|ed|ies)\b|\bonline\s+(?:order|store|purchase)|\border\s+online\b|\bcustomers?\s+aged\b|\btobacco\b|\bcigars?\b|\bgift\s*cards?\b|\bcheckout\b|\bwebsite\b/i;
/** "21 to drink" is the law, not a door rule — it never counts as a policy statement. */
const DRINK_CONTEXT = /\bto\s+(?:drink|consume|purchase|order|buy)\b|\bdrinking\s+age\b/i;
const ENTRY_CUE =
  /\b(?:enter|entry|entrance|admission|admitted|admit|door|cover|guest\s*list|guestlist|venue|club|event|party|welcome|allowed|only|no\s+exceptions|id\s+required|valid\s+id|photo\s+id|with\s+(?:a\s+)?(?:valid\s+)?id)\b/i;

const IS_21 = /\b21\s*(?:\+|and\s+(?:over|up|older)|&\s*(?:over|up))|\bmust\s+be\s+21\b|\b21\s+to\s+enter\b|\bages?\s+21\s*(?:\+|and\s+(?:over|up))/i;
const IS_18 = /\b18\s*(?:\+|and\s+(?:over|up|older)|&\s*(?:over|up))|\bmust\s+be\s+18\b|\b18\s+to\s+enter\b|\bages?\s+18\s*(?:\+|and\s+(?:over|up))/i;
/** "18 to enter, 21 to drink" — 18-20 get in, so it is neither a clean 18+ nor 21+. */
const IS_MIXED = /\b18\s*(?:\+|and\s+(?:over|up))?\s*to\s+(?:enter|party|get\s+in)\b[^.\n]{0,40}\b21\s*(?:\+|and\s+(?:over|up))?\s*to\s+drink\b|\b21\s+to\s+drink\b[^.\n]{0,40}\b18\s+to\s+enter\b/i;

/**
 * The published age policy, mapped to the column's three values
 * ('18+' | '21+' | 'mixed'). Null when the page never states one, and null
 * when two lines of the same page contradict each other.
 */
export function detectAgePolicy(text: string): AgeFinding | null {
  const hits: AgeFinding[] = [];       // sentences that state a DOOR policy
  const mentions = new Set<AgeValue>(); // every age rule on the page, for the contradiction check
  for (const line of candidateLines(text, AGE_WORD, 200)) {
    if (AGE_FALSE_POSITIVE.test(line) || AGE_FINE_PRINT.test(line)) continue;
    if (IS_MIXED.test(line)) { hits.push({ value: "mixed", evidence: line }); mentions.add("mixed"); continue; }
    if (DRINK_CONTEXT.test(line) || COMMERCE_CONTEXT.test(line)) continue;
    const value: AgeValue | null = IS_21.test(line) && IS_18.test(line) ? null
      : IS_21.test(line) ? "21+" : IS_18.test(line) ? "18+" : null;
    if (IS_21.test(line) && IS_18.test(line)) return null; // both ages, no enter/drink split → ambiguous
    if (!value) continue;
    mentions.add(value);
    // No entry wording in the sentence → it is about being served, not about the door.
    if (ENTRY_CUE.test(line)) hits.push({ value, evidence: line });
  }
  const mixed = hits.find((h) => h.value === "mixed");
  if (mixed) return mixed;
  if (hits.length === 0) return null;
  if (mentions.has("18+") && mentions.has("21+")) return null; // the page contradicts itself
  const distinct = new Set(hits.map((h) => h.value));
  return distinct.size === 1 ? hits[0] : null;
}

/** Cheap pre-filter: is it even worth paying for a model call on this page? */
export function hasDoorFactSignal(text: string): boolean {
  return DOOR_WORD.test(text) || DRESS_WORD.test(text) || AGE_WORD.test(text);
}

/** Whitespace/case-insensitive literal containment — the model's quote must be ON the page. */
export function quoteAppearsInText(text: string, quote: string | undefined): boolean {
  if (!quote || quote.trim().length < 6) return false;
  const norm = (s: string) => s.toLowerCase().replace(/[\s ]+/g, " ").replace(/[’‘]/g, "'").replace(/[–—]/g, "-").trim();
  return norm(text).includes(norm(quote));
}

/** Links that plausibly carry door facts: info/about/faq/policies/events/vip. */
const DOOR_LINK = /info|about|faq|polic|rules|dress|cover|admission|door|entry|vip|table|bottle|guest\s*list|guestlist|reservation|night|event|hours|visit/i;
const ASSET_PATH = /\.(pdf|jpe?g|png|webp|gif|svg|css|js|json|xml|ico|woff2?|mp4)$/i;

export function doorFactLinks(html: string, base: string, limit = 5): string[] {
  const origin = new URL(base).origin;
  const self = base.split("?")[0].replace(/\/$/, "");
  const seen = new Set<string>();
  const byHref: string[] = [];
  const byLabel: string[] = [];
  for (const m of html.matchAll(/<a\s[^>]*?href=["']([^"'#]+)["'][^>]*>([\s\S]{0,160}?)<\/a>/gi)) {
    const href = m[1];
    const label = m[2].replace(/<[^>]+>/g, " ");
    const hrefHit = DOOR_LINK.test(href);
    if (!hrefHit && !DOOR_LINK.test(label)) continue;
    try {
      const u = new URL(href, base);
      if (u.origin !== origin || ASSET_PATH.test(u.pathname)) continue;
      const clean = u.toString().split("?")[0];
      const key = clean.replace(/\/$/, "");
      if (key === self || seen.has(key)) continue;
      seen.add(key);
      (hrefHit ? byHref : byLabel).push(clean);
    } catch { /* bad href */ }
  }
  const rank = (u: string) => (/info|faq|polic|rules|dress|cover|door|vip|guest/i.test(new URL(u).pathname) ? 0 : 1);
  byHref.sort((a, b) => rank(a) - rank(b));
  return [...byHref, ...byLabel].slice(0, limit);
}

/** How much page text the model sees (~3.5k tokens). */
export const PROMPT_TEXT_CHARS = 14_000;

export function doorFactsPrompt(venue: { name: string; type: string; city: string }, text: string, maxChars = PROMPT_TEXT_CHARS): string {
  return `You read a venue's own website text and report ONLY what it explicitly states about getting in the door. Venue: "${venue.name}" (${venue.type}, ${venue.city}).
Return ONLY JSON, no prose, no code fence:
{"cover":{"men":null,"women":null,"quote":""},"dress_code":{"value":"","quote":""},"age_policy":{"value":"18+|21+|mixed","quote":""}}
RULES:
- "quote" must be copied VERBATIM from the text below, one sentence, including the numbers. If you cannot copy a sentence that states the fact, the whole field is null. A field with no quote is discarded.
- cover: the price to GET IN, in whole dollars. "no cover" is 0 — that is a fact, not an empty value. A price with no door word next to it is a food/drink price, not a cover. A "cover band" is music, not a cover charge. If the cover depends on a condition ("free before 11", "with RSVP"), still quote it — do not strip the condition out of the quote.
- dress_code: copy the venue's own words ("no hats or athletic wear", "dress to impress"). Never paraphrase, never translate, never invent a rule the text does not print.
- age_policy: the age needed to GET IN, not the age needed to drink. "21+" only if the text says 21 and over to enter / must be 21 to enter; "18+" if 18 and over get in; "mixed" if it says something like 18 to enter, 21 to drink. The fine print of a drink promo ("Must be 21+. Void where prohibited.") is the drinking age, which is the law everywhere and is NOT this venue's door policy — return null for it. Otherwise null.
- Never guess, infer from the venue type, or repeat what is "usual" for this kind of place. An empty answer is correct; an invented one is not.

TEXT:
${text.slice(0, maxChars)}`;
}
