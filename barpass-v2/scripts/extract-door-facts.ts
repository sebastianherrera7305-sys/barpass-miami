/**
 * Door facts from each venue's own website: cover, dress code, age policy.
 *
 * Measured 2026-09-16 on 4.264 servable venues: cover_men, cover_women and
 * dress_code are 0% filled, age_policy is 2.569 rows of the seeded '21+'
 * default and 1.848 NULLs. Those are the questions someone asks standing on
 * the sidewalk — "how much to get in, can I wear this, will they let me in" —
 * and the catalogue has no answer at all.
 *
 * Same contract as extract-drink-menus.ts, which this copies:
 *   model proposes → rules verify → nothing that fails verification is written.
 * A value is written ONLY when the model returns a sentence copied verbatim
 * from the page, that sentence is literally present in the fetched text, and
 * the pure detectors in door-facts-rules.ts read the same value out of that
 * same sentence. Anything else is a NULL, which is a fact.
 *
 * Writes (with --apply):
 *   venues.cover_men / cover_women   whole dollars; "no cover" is 0, not NULL
 *   venues.dress_code                the venue's own words, never paraphrased
 *   venues.age_policy                '18+' | '21+' | 'mixed' (column check)
 *   venues.field_sources             per field: source, method, model, url, at,
 *                                    fetched_at + the literal sentence that
 *                                    justifies it. No sentence → no write.
 *   A venue whose site was read and states none of this gets
 *   {result: "none_published"} so it is not re-crawled every run.
 *
 * Deliberately NOT written: a conditional cover. "Ladies free before 11" is
 * free under a condition; cover_women = 0 would tell a woman arriving at 1am
 * she gets in free. The phrase is kept in provenance instead.
 *
 * Usage:
 *   node --env-file=.env.local --import tsx scripts/extract-door-facts.ts --help
 *   ... --city Gainesville --limit 10          # dry run, prints what it would write
 *   ... --city Gainesville --apply             # write
 *   ... --only <venue-id> --apply              # one venue
 */
import { createClient } from "@supabase/supabase-js";
// @ts-expect-error — ws ships no types here; same shim every other script uses.
import ws from "ws";
import { htmlToText } from "./drink-menu-rules";
import {
  doorFactLinks, doorFactsPrompt, hasDoorFactSignal, quoteAppearsInText,
  detectCover, detectDressCode, detectAgePolicy, type AgeValue,
} from "./door-facts-rules";

const args = process.argv.slice(2);
const flag = (n: string) => { const i = args.indexOf(n); return i === -1 ? undefined : args[i + 1]; };

if (args.includes("--help") || args.includes("-h")) {
  console.log(`extract-door-facts — cover, dress code and age policy from each venue's own website.

  --city <name>       venues to try (default: Miami). Ignored with --only.
  --limit <n>         stop after n venues (default: all)
  --only <venue-id>   one venue by id (uuid)
  --apply             write to Supabase (default: dry run, prints what it would write)
  --force             re-check venues that already have these fields, and overwrite
                      manual_research / user_report provenance (off by default)
  --recheck-days <n>  re-try venues recorded "none_published" older than n days (default 90)
  --help              this text

Env (from .env.local): NEXT_PUBLIC_SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, NVIDIA_API_KEY`);
  process.exit(0);
}

const CITY = flag("--city") ?? "Miami";
const LIMIT = Number(flag("--limit") ?? 9999);
const ONLY = flag("--only");
const APPLY = args.includes("--apply");

// Misma compuerta que extract-drink-menus.ts: `--apply` decide si se ESCRIBE,
// no si se GASTA. Sin `--spend`, el script recorre y cuenta las llamadas al
// modelo que haría, sin hacer ninguna.
const SPEND = args.includes("--spend") || process.env.AI_SPEND === "1";
let wouldSpendCalls = 0;
const FORCE = args.includes("--force");
const RECHECK_DAYS = Number(flag("--recheck-days") ?? 90);

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const NVIDIA_KEY = process.env.NVIDIA_API_KEY;
if (!SUPABASE_URL || !SERVICE_KEY) { console.error("NEXT_PUBLIC_SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY missing (run with node --env-file=.env.local)"); process.exit(1); }
if (!NVIDIA_KEY) { console.error("NVIDIA_API_KEY missing — the extractor needs the model"); process.exit(1); }
const MODEL = "openai/gpt-oss-20b";
const MAX_PAGES = 5;
const MODEL_PACE_MS = 1500;
const MODEL_RETRIES = 4;
const PAGE_SIZE = 1000;   // PostgREST caps a response at 1000 rows; read in pages or lie about the total.
const DOOR_FIELDS = ["cover_men", "cover_women", "dress_code", "age_policy"] as const;
const HUMAN_SOURCES = new Set(["manual_research", "user_report"]);
const UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1";

interface FieldSource {
  source?: string; method?: string; model?: string; confidence?: string;
  at?: string; fetched_at?: string; url?: string; pages?: string[];
  result?: string; notes?: string; [k: string]: unknown;
}
interface DbVenue {
  id: string; name: string; city: string; type: string; website: string | null;
  cover_men: number | null; cover_women: number | null; dress_code: string | null; age_policy: string | null;
  field_sources: Record<string, FieldSource | undefined> | null;
}

const supabase = createClient(SUPABASE_URL, SERVICE_KEY, { realtime: { transport: ws as unknown as typeof WebSocket } });

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
let lastFetchError = "";

async function fetchText(url: string, ms = 12000): Promise<{ html: string; finalUrl: string } | null> {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), ms);
  lastFetchError = "";
  try {
    const res = await fetch(url, { headers: {
      "User-Agent": UA,
      Accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      "Accept-Language": "en-US,en;q=0.9",
      "Sec-Fetch-Dest": "document", "Sec-Fetch-Mode": "navigate", "Sec-Fetch-Site": "none",
      "Upgrade-Insecure-Requests": "1",
    }, signal: ctrl.signal, redirect: "follow" });
    if (!res.ok) { lastFetchError = `HTTP ${res.status}`; return null; }
    const ct = res.headers.get("content-type") ?? "";
    if (!ct.includes("html")) { lastFetchError = `not HTML (${ct.split(";")[0] || "no content-type"})`; return null; }
    return { html: await res.text(), finalUrl: res.url };
  } catch (e) {
    lastFetchError = e instanceof Error && e.name === "AbortError" ? `timeout after ${ms / 1000}s`
      : `${e instanceof Error ? (e.cause instanceof Error ? e.cause.message : e.message) : e}`;
    return null;
  } finally { clearTimeout(t); }
}

interface ModelAnswer {
  cover?: { men?: unknown; women?: unknown; quote?: unknown } | null;
  dress_code?: { value?: unknown; quote?: unknown } | null;
  age_policy?: { value?: unknown; quote?: unknown } | null;
}

async function askModel(venue: DbVenue, text: string): Promise<ModelAnswer | null> {
  const prompt = doorFactsPrompt(venue, text);
  let json: { choices?: Array<{ message?: { content?: string } }> } | null = null;
  if (!SPEND) { wouldSpendCalls++; return null; }
  for (let attempt = 1; attempt <= MODEL_RETRIES && !json; attempt++) {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), 120_000);
    try {
      const res = await fetch("https://integrate.api.nvidia.com/v1/chat/completions", {
        method: "POST",
        headers: { Authorization: `Bearer ${NVIDIA_KEY}`, "Content-Type": "application/json" },
        body: JSON.stringify({ model: MODEL, reasoning_effort: "low", temperature: 0, max_tokens: 800,
          messages: [{ role: "user", content: prompt }] }),
        signal: ctrl.signal,
      });
      if (res.status === 429 || res.status >= 500) {
        const wait = 10_000 * 2 ** (attempt - 1);
        console.error(`  model HTTP ${res.status} for ${venue.name} — attempt ${attempt}/${MODEL_RETRIES}, waiting ${wait / 1000}s`);
        await res.text().catch(() => undefined);
        if (attempt < MODEL_RETRIES) await sleep(wait);
        continue;
      }
      if (!res.ok) { console.error(`  model HTTP ${res.status} for ${venue.name}`); return null; }
      json = await res.json();
    } catch (e) {
      console.error(`  model call failed for ${venue.name}: ${e instanceof Error ? e.name : e}`);
      return null;
    } finally { clearTimeout(timer); await sleep(MODEL_PACE_MS); }
  }
  const content = json?.choices?.[0]?.message?.content ?? "";
  const m = content.match(/\{[\s\S]*\}/);
  if (!m) return null;
  try { return JSON.parse(m[0]) as ModelAnswer; } catch { return null; }
}

/** One verified door fact: a value, and the page sentence that proves it. */
interface Verified<T> { value: T; quote: string; method: string }

const asQuote = (q: unknown) => (typeof q === "string" ? q.trim() : "");
const asInt = (v: unknown) => (typeof v === "number" && Number.isInteger(v) ? v : null);

/**
 * Accept the model's cover only if its quote is on the page AND the pure
 * detector reads the same numbers out of that quote. A conditional quote
 * ("free before 11") is reported but never turned into a value.
 */
function verifyCover(ans: ModelAnswer, text: string):
  { men: number | null; women: number | null; quote: string; method: string; conditional: boolean } | null {
  const quote = asQuote(ans.cover?.quote);
  const fromModel = quote && quoteAppearsInText(text, quote) ? detectCover(quote) : null;
  const hit = fromModel ?? detectCover(text);
  if (!hit) return null;
  const method = fromModel ? "llm_quote+rule_verify" : "rule_detect";
  const evidence = fromModel ? quote : hit.evidence;
  if (hit.conditional) return { men: null, women: null, quote: evidence, method, conditional: true };
  // The model's own numbers must agree with what the detector read, when it gave any.
  const mMen = asInt(ans.cover?.men), mWomen = asInt(ans.cover?.women);
  if (fromModel && ((mMen !== null && mMen !== hit.men) || (mWomen !== null && mWomen !== hit.women))) return null;
  return { men: hit.men, women: hit.women, quote: evidence, method, conditional: false };
}

function verifyDress(ans: ModelAnswer, text: string): Verified<string> | null {
  const quote = asQuote(ans.dress_code?.quote);
  if (quote && quoteAppearsInText(text, quote)) {
    const hit = detectDressCode(quote);
    if (hit) return { value: hit.value, quote, method: "llm_quote+rule_verify" };
  }
  const fallback = detectDressCode(text);
  return fallback ? { value: fallback.value, quote: fallback.evidence, method: "rule_detect" } : null;
}

function verifyAge(ans: ModelAnswer, text: string): Verified<AgeValue> | null {
  const quote = asQuote(ans.age_policy?.quote);
  if (quote && quoteAppearsInText(text, quote)) {
    const hit = detectAgePolicy(quote);
    const claimed = typeof ans.age_policy?.value === "string" ? ans.age_policy.value : null;
    if (hit && (claimed === null || claimed === hit.value)) return { value: hit.value, quote, method: "llm_quote+rule_verify" };
  }
  const fallback = detectAgePolicy(text);
  return fallback ? { value: fallback.value, quote: fallback.evidence, method: "rule_detect" } : null;
}

function daysSince(iso: string | undefined): number {
  if (!iso) return Infinity;
  const t = Date.parse(iso);
  return Number.isFinite(t) ? (Date.now() - t) / 86_400_000 : Infinity;
}

/** A field a human filled in is worth more than a re-scrape. */
function humanOwned(v: DbVenue, field: string): boolean {
  const s = v.field_sources?.[field]?.source;
  return !!s && HUMAN_SOURCES.has(s) && !FORCE;
}

function skipReason(v: DbVenue): string | null {
  if (ONLY || FORCE) return null;
  const prov = v.field_sources?.door_facts;
  if (prov?.result === "none_published" && daysSince(prov.fetched_at ?? prov.at) < RECHECK_DAYS) {
    return `site checked ${prov.fetched_at ?? prov.at}: publishes no door facts (re-try after ${RECHECK_DAYS}d or --force)`;
  }
  if (DOOR_FIELDS.every((f) => humanOwned(v, f))) return "every door field is human-sourced";
  return null;
}

/** PostgREST returns at most 1000 rows; a script that forgets this reports a city it never read. */
async function fetchAll(): Promise<DbVenue[]> {
  const out: DbVenue[] = [];
  for (let from = 0; ; from += PAGE_SIZE) {
    let q = supabase.from("venues")
      .select("id,name,city,type,website,cover_men,cover_women,dress_code,age_policy,field_sources")
      .is("excluded_reason", null)
      .or("business_status.is.null,business_status.neq.CLOSED_PERMANENTLY")
      .not("website", "is", null).order("name").range(from, from + PAGE_SIZE - 1);
    q = ONLY ? q.eq("id", ONLY) : q.eq("city", CITY);
    const { data, error } = await q;
    if (error) throw error;
    const page = (data ?? []) as unknown as DbVenue[];
    out.push(...page);
    if (page.length < PAGE_SIZE) return out;
  }
}

async function main() {
  const updateVenue = async (id: string, patch: Record<string, unknown>): Promise<string | null> => {
    let last = "";
    for (let attempt = 1; attempt <= 3; attempt++) {
      const { error } = await supabase.from("venues").update(patch).eq("id", id);
      if (!error) return null;
      last = error.message;
      if (attempt < 3) await sleep(3000 * attempt);
    }
    return last;
  };

  const all = await fetchAll();
  const venues: DbVenue[] = [];
  for (const v of all) {
    const why = skipReason(v);
    if (why) { console.log(`· ${v.name}: skip — ${why}`); continue; }
    venues.push(v);
    if (venues.length >= LIMIT) break;
  }
  console.log(`${venues.length} venues ${ONLY ? "by id" : `in ${CITY}`} to try, of ${all.length} with a website (${APPLY ? "APPLY" : "dry run"})\n`);

  let withFacts = 0, written = 0, noneRecorded = 0, conditionalOnly = 0;
  let consecutiveNetworkFailures = 0;
  for (const v of venues) {
    const home = await fetchText(v.website!);
    if (!home) {
      console.log(`- ${v.name}: site unreachable (${lastFetchError}) ${v.website}`);
      if (/ENOTFOUND|EAI_AGAIN|ECONNREFUSED|ETIMEDOUT|fetch failed/i.test(lastFetchError)) {
        if (++consecutiveNetworkFailures >= 5) {
          console.error(`\nSTOPPING: ${consecutiveNetworkFailures} network failures in a row — this machine lost DNS or connectivity, the sites are probably fine.`);
          console.error("Nothing was recorded for them. Re-run when the network is back.");
          break;
        }
      } else consecutiveNetworkFailures = 0;
      continue;
    }
    consecutiveNetworkFailures = 0;
    const links = doorFactLinks(home.html, home.finalUrl, MAX_PAGES - 1);
    const pages = [...links.filter((l) => l !== home.finalUrl), home.finalUrl].slice(-MAX_PAGES);
    let text = "";
    const used: string[] = [];
    for (const url of pages) {
      const page = url === home.finalUrl ? home : await fetchText(url);
      if (!page) continue;
      const t = htmlToText(page.html);
      if (hasDoorFactSignal(t)) { text += `\n\n[${url}]\n${t}`; used.push(url); }
    }

    const fetchedAt = new Date().toISOString();
    const today = fetchedAt.slice(0, 10);
    const fs = { ...(v.field_sources ?? {}) } as Record<string, FieldSource | undefined>;
    const ans = used.length > 0 ? await askModel(v, text) : {};
    if (!ans) { console.log(SPEND ? `- ${v.name}: model call failed (nothing recorded)` : `- ${v.name}: se saltea la llamada al modelo (simulación)`); continue; }

    const cover = used.length > 0 ? verifyCover(ans, text) : null;
    const dress = used.length > 0 ? verifyDress(ans, text) : null;
    const age = used.length > 0 ? verifyAge(ans, text) : null;
    const gotValue = (cover !== null && !cover.conditional) || dress !== null || age !== null;

    if (!gotValue) {
      const why = used.length === 0 ? `no door-fact wording on site (${pages.length} pages)`
        : cover?.conditional ? `cover stated only under a condition — "${cover.quote.slice(0, 80)}" (not written)`
        : "door wording on site but nothing verifiable";
      console.log(`- ${v.name}: ${why}`);
      if (cover?.conditional) conditionalOnly++;
      if (APPLY) {
        fs.door_facts = { source: "venue website", method: used.length === 0 ? "no_door_text" : "llm_extract+rule_verify",
          model: used.length === 0 ? undefined : MODEL, result: "none_published", at: today, fetched_at: fetchedAt,
          url: home.finalUrl, pages,
          notes: `Site reachable; ${pages.length} page(s) read; no cover, dress code or age policy stated.${cover?.conditional ? ` Conditional cover seen, not written: "${cover.quote.slice(0, 160)}"` : ""} Re-try after ${RECHECK_DAYS} days.` };
        const upErr = await updateVenue(v.id, { field_sources: fs });
        if (upErr) console.error(`  provenance write failed for ${v.name}: ${upErr}`); else noneRecorded++;
      }
      continue;
    }

    withFacts++;
    const patch: Record<string, unknown> = {};
    const prov = (method: string, quote: string): FieldSource => ({
      source: "venue website", method, model: method.startsWith("llm") ? MODEL : undefined, confidence: "high",
      at: today, fetched_at: fetchedAt, url: used[0], pages: used,
      notes: `Page states: "${quote.slice(0, 240)}"`,
    });
    const lines: string[] = [];
    if (cover && !cover.conditional) {
      for (const [field, value] of [["cover_men", cover.men], ["cover_women", cover.women]] as const) {
        if (value === null || humanOwned(v, field)) continue;
        patch[field] = value;
        fs[field] = prov(cover.method, cover.quote);
        lines.push(`     ${field.padEnd(12)} $${value}   ← "${cover.quote.slice(0, 90)}"`);
      }
    }
    if (dress && !humanOwned(v, "dress_code")) {
      patch.dress_code = dress.value;
      fs.dress_code = prov(dress.method, dress.quote);
      lines.push(`     dress_code   ${dress.value.slice(0, 60)}   ← "${dress.quote.slice(0, 90)}"`);
    }
    if (age && !humanOwned(v, "age_policy")) {
      patch.age_policy = age.value;
      fs.age_policy = prov(age.method, age.quote);
      lines.push(`     age_policy   ${age.value}   ← "${age.quote.slice(0, 90)}"`);
    }
    console.log(`+ ${v.name}: ${lines.length} field(s) verified`);
    for (const l of lines) console.log(l);
    if (!APPLY || lines.length === 0) continue;
    patch.field_sources = fs;
    const upErr = await updateVenue(v.id, patch);
    if (upErr) console.error(`  write failed for ${v.name}: ${upErr}`); else written++;
  }
  if (!SPEND) {
    console.log(`\n[SIMULACIÓN] No se llamó a ningún modelo y no se gastó nada.`);
    console.log(`  llamadas que HARÍA: ${wouldSpendCalls}`);
    console.log(`  para ejecutarlo de verdad: agregá --spend (y --apply para guardar)`);
  }

  console.log(`\nDone: ${withFacts}/${venues.length} venues published a verifiable door fact (${conditionalOnly} stated a conditional cover, deliberately not written)${APPLY ? `, ${written} written, ${noneRecorded} recorded as none_published` : ""}.`);
}

main().catch((e) => { console.error(e); process.exit(1); });
