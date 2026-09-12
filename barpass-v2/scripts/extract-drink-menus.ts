/**
 * Drink menus with REAL prices, from each venue's own website.
 *
 * "Lo que se necesita es saber qué tragos venden, dónde, cuándo y a cuánto"
 * (2026-09-08). This script visits a venue's website, finds the menu /
 * drinks / happy-hour pages, and asks a model to pull out ONLY items with an
 * explicit price. It never invents: no price in the text → no item, and every
 * price the model returns must literally appear in the page text
 * (scripts/drink-menu-rules.ts, unit-tested) or the item is dropped.
 *
 * Writes (with --apply):
 *   venues.popular_drinks    top 6 items [{name, price, emoji}] — iOS and the
 *                            web venue page render this as-is
 *   venues.happy_hour_until  "HH:MM" ONLY when the site states one unambiguous
 *                            end time (multi-window / "til close" → not written)
 *   venues.field_sources     provenance for both fields: source, method, model,
 *                            url + every page read, fetched_at, and the full
 *                            structured item list. A venue whose site was
 *                            reachable but published no priced drinks gets
 *                            {result: "none_published"} so it is not re-crawled
 *                            every run (see venue_field_provenance.sql).
 *
 * Never overwrites a value whose provenance is manual_research or user_report
 * (those cost human effort) unless --force is passed.
 *
 * Usage:
 *   npm run extract:menus -- --help
 *   npm run extract:menus -- --city Miami --limit 5           # dry run
 *   npm run extract:menus -- --city Miami --apply             # write
 *   npm run extract:menus -- --apply --only <venue-id>        # one venue
 *   npm run extract:menus -- --apply --ids-file retry.tsv     # "<id>\t<city>" lines
 *   npm run extract:menus -- --city Miami --apply --force     # re-extract venues that already have drinks
 *   npm run extract:menus -- --city Miami --recheck-days 30   # re-try "none_published" older than 30 days (default 90)
 */
import { createClient } from "@supabase/supabase-js";
// @ts-expect-error — ws ships no types here; same shim every other script uses for Node 20 realtime.
import ws from "ws";
import {
  htmlToText, menuLinks, hasPricedText, sanitizeDrinks, pickTopDrinks, happyHourEnd, extractionPrompt,
  type Extracted, type ExtractedDrink, type ExtractedHappyHour,
} from "./drink-menu-rules";

const args = process.argv.slice(2);
const flag = (n: string) => { const i = args.indexOf(n); return i === -1 ? undefined : args[i + 1]; };

if (args.includes("--help") || args.includes("-h")) {
  console.log(`extract-drink-menus — real drink prices from each venue's own website.

  --city <name>        venues to try (default: Miami). Ignored with --only / --ids-file.
  --limit <n>          stop after n venues (default: all)
  --only <venue-id>    one venue by id (uuid)
  --ids-file <path>    "<venue id>\\t<city>" lines, one process for a whole retry list
  --apply              write to Supabase (default: dry run, prints what it would write)
  --force              re-extract venues that already have popular_drinks, and overwrite
                       manual_research / user_report provenance (off by default)
  --recheck-days <n>   re-try venues recorded as "none_published" older than n days (default 90)
  --help               this text

Env (from .env.local): NEXT_PUBLIC_SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, NVIDIA_API_KEY`);
  process.exit(0);
}

const CITY = flag("--city") ?? "Miami";
const LIMIT = Number(flag("--limit") ?? 9999);
const ONLY = flag("--only");
/** A file of "<venue id>\t<city>" lines — one process for a whole retry list
 * instead of one npm/tsx boot per venue (2026-09-08: the per-venue loop was
 * spending ~2 min each on startup + a full catalog query, for a 3.5h run). */
const IDS_FILE = flag("--ids-file");
const APPLY = args.includes("--apply");
const FORCE = args.includes("--force");
const RECHECK_DAYS = Number(flag("--recheck-days") ?? 90);

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const NVIDIA_KEY = process.env.NVIDIA_API_KEY;
if (!SUPABASE_URL || !SERVICE_KEY) { console.error("NEXT_PUBLIC_SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY missing (run via npm run extract:menus so .env.local loads)"); process.exit(1); }
if (!NVIDIA_KEY) { console.error("NVIDIA_API_KEY missing — the extractor needs the model"); process.exit(1); }
const MODEL = "openai/gpt-oss-20b";
const MAX_PAGES = 6;

/** Provenance entry for one field, as stored in venues.field_sources.<field>. */
interface FieldSource {
  source?: string;
  method?: string;
  model?: string;
  confidence?: string;
  date?: string;
  at?: string;
  fetched_at?: string;
  url?: string;
  pages?: string[];
  result?: string;
  notes?: string;
  items?: ExtractedDrink[];
  happy_hour?: ExtractedHappyHour;
  [k: string]: unknown;
}

interface DbVenue {
  id: string; name: string; city: string; type: string; website: string | null;
  popular_drinks: unknown; happy_hour_until: string | null;
  field_sources: Record<string, FieldSource | undefined> | null;
}

const UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1";
const HUMAN_SOURCES = new Set(["manual_research", "user_report"]);

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/** Why the last fetchText() returned null — printed so a failed site has a reason in the log
 * (bot wall vs timeout vs non-HTML), which is what decides whether a human must collect prices. */
let lastFetchError = "";

async function fetchText(url: string, ms = 12000): Promise<{ html: string; finalUrl: string } | null> {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), ms);
  lastFetchError = "";
  try {
    const res = await fetch(url, { headers: { "User-Agent": UA, Accept: "text/html,*/*" }, signal: ctrl.signal, redirect: "follow" });
    if (!res.ok) { lastFetchError = `HTTP ${res.status}`; return null; }
    const ct = res.headers.get("content-type") ?? "";
    if (!ct.includes("html")) { lastFetchError = `not HTML (${ct.split(";")[0] || "no content-type"})`; return null; }
    return { html: await res.text(), finalUrl: res.url };
  } catch (e) {
    lastFetchError = e instanceof Error && e.name === "AbortError" ? `timeout after ${ms / 1000}s` : `${e instanceof Error ? e.cause instanceof Error ? e.cause.message : e.message : e}`;
    return null;
  } finally { clearTimeout(t); }
}

/** Minimum gap between two model calls. NIM answers 429 to rapid calls (CLAUDE.md, 2026-09-06). */
const MODEL_PACE_MS = 1500;
const MODEL_RETRIES = 4;

/** Ask the model, then keep only what the rules module can verify against the page text. */
async function extract(venue: DbVenue, text: string): Promise<Extracted | null> {
  const prompt = extractionPrompt(venue, text);
  let json: { choices?: Array<{ message?: { content?: string } }> } | null = null;
  for (let attempt = 1; attempt <= MODEL_RETRIES && !json; attempt++) {
    // Bounded: one hung NIM call (undici headers timeout at 5 min) took the
    // whole run down on the first dry run. 120s is generous for a 1.2K-token reply.
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), 120_000);
    try {
      const res = await fetch("https://integrate.api.nvidia.com/v1/chat/completions", {
        method: "POST",
        headers: { Authorization: `Bearer ${NVIDIA_KEY}`, "Content-Type": "application/json" },
        body: JSON.stringify({ model: MODEL, reasoning_effort: "low", temperature: 0, max_tokens: 1200,
          messages: [{ role: "user", content: prompt }] }),
        signal: ctrl.signal,
      });
      if (res.status === 429 || res.status >= 500) {
        // Rate-limited or upstream hiccup: back off (10s, 20s, 40s) and retry instead of
        // dropping the venue — before this, a 429 silently skipped it with nothing recorded.
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
  if (!json) return null;
  const content: string = json.choices?.[0]?.message?.content ?? "";
  const m = content.match(/\{[\s\S]*\}/);
  if (!m) return null;
  let parsed: { drinks?: unknown; happy_hour?: ExtractedHappyHour | null };
  try { parsed = JSON.parse(m[0]); } catch { return null; }
  const drinks = sanitizeDrinks(parsed.drinks, text);
  const hh = parsed.happy_hour && typeof parsed.happy_hour === "object" && (parsed.happy_hour.hours || parsed.happy_hour.deals)
    ? { days: str(parsed.happy_hour.days), hours: str(parsed.happy_hour.hours), deals: str(parsed.happy_hour.deals) }
    : null;
  return { drinks, happy_hour: hh };
}

function str(v: unknown): string | undefined {
  return typeof v === "string" && v.trim() ? v.trim().slice(0, 200) : undefined;
}

function hasDrinks(v: DbVenue): boolean {
  if (Array.isArray(v.popular_drinks)) return v.popular_drinks.length > 0;
  if (typeof v.popular_drinks === "string") { try { const a = JSON.parse(v.popular_drinks); return Array.isArray(a) && a.length > 0; } catch { return false; } }
  return false;
}

function daysSince(iso: string | undefined): number {
  if (!iso) return Infinity;
  const t = Date.parse(iso);
  return Number.isFinite(t) ? (Date.now() - t) / 86_400_000 : Infinity;
}

/** Why this venue is skipped on a normal run, or null to proceed. */
function skipReason(v: DbVenue): string | null {
  if (ONLY || IDS_FILE) return null; // explicit lists are always tried
  const prov = v.field_sources?.popular_drinks;
  if (prov?.source && HUMAN_SOURCES.has(prov.source) && !FORCE) return `provenance is ${prov.source} — not overwriting without --force`;
  if (prov?.result === "none_published" && !FORCE && daysSince(prov.fetched_at ?? prov.at ?? prov.date) < RECHECK_DAYS) {
    return `site checked ${prov.fetched_at ?? prov.at ?? prov.date}: no priced drinks published (re-try after ${RECHECK_DAYS}d or --force)`;
  }
  return null;
}

async function main() {
  const supabase = createClient(SUPABASE_URL!, SERVICE_KEY!, { realtime: { transport: ws as unknown as typeof WebSocket } });
  /** One venue update, retried through a transient Supabase hiccup.
   * 2026-09-12: a "Gateway Timeout" on the provenance write lost the finding
   * outright, so the venue would be re-crawled (and re-billed) next run. */
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
  let q = supabase.from("venues").select("id,name,city,type,website,popular_drinks,happy_hour_until,field_sources")
    .is("excluded_reason", null)
    .or("business_status.is.null,business_status.neq.CLOSED_PERMANENTLY")
    .not("website", "is", null).order("name");
  if (IDS_FILE) {
    const ids = (await import("node:fs")).readFileSync(IDS_FILE, "utf8")
      .split("\n").map((l) => l.split("\t")[0].trim()).filter(Boolean);
    q = q.in("id", ids);
  } else if (ONLY) {
    q = q.eq("id", ONLY);
  } else {
    q = q.eq("city", CITY);
  }
  const { data, error } = await q;
  if (error) throw error;
  const all = data as DbVenue[];
  const candidates = all.filter((v) => FORCE || ONLY || IDS_FILE || !hasDrinks(v));
  const venues: DbVenue[] = [];
  for (const v of candidates) {
    const why = skipReason(v);
    if (why) { console.log(`· ${v.name}: skip — ${why}`); continue; }
    venues.push(v);
    if (venues.length >= LIMIT) break;
  }
  console.log(`${venues.length} venues ${IDS_FILE ? "from list" : ONLY ? "by id" : `in ${CITY}`} to try (${APPLY ? "APPLY" : "dry run"})`);

  let withMenu = 0, written = 0, noneRecorded = 0;
  for (const v of venues) {
    const home = await fetchText(v.website!);
    if (!home) { console.log(`- ${v.name}: site unreachable (${lastFetchError}) ${v.website}`); continue; }
    const links = menuLinks(home.html, home.finalUrl, MAX_PAGES - 1);
    // Menu pages first, the home page last: the model reads a bounded slice
    // of this text, and a home page rarely holds the drink list.
    const pages = [...links.filter((l) => l !== home.finalUrl), home.finalUrl].slice(-MAX_PAGES);
    let text = "";
    const used: string[] = [];
    for (const url of pages) {
      const page = url === home.finalUrl ? home : await fetchText(url);
      if (!page) continue;
      const t = htmlToText(page.html);
      if (hasPricedText(t)) { text += `\n\n[${url}]\n${t}`; used.push(url); }
    }
    const fetchedAt = new Date().toISOString();
    const today = fetchedAt.slice(0, 10);
    const fs = { ...(v.field_sources ?? {}) } as Record<string, FieldSource | undefined>;

    const ex = hasPricedText(text) ? await extract(v, text) : { drinks: [], happy_hour: null };
    if (!ex) { console.log(`- ${v.name}: model call failed (nothing recorded)`); continue; }

    if (ex.drinks.length === 0) {
      console.log(`- ${v.name}: ${used.length === 0 ? `no priced text on site (${pages.length} pages)` : "prices on site but no verifiable drink items"}`);
      // Record the finding so the venue is not re-crawled next run — unless it
      // already has drinks (a --force re-check that found nothing keeps them).
      if (APPLY && !hasDrinks(v)) {
        fs.popular_drinks = { source: "venue website menu", method: used.length === 0 ? "no_priced_text" : "llm_extract", model: used.length === 0 ? undefined : MODEL,
          result: "none_published", at: today, fetched_at: fetchedAt, url: home.finalUrl, pages,
          notes: `Site reachable; ${pages.length} page(s) read; no drink with a printed price found. Re-try after ${RECHECK_DAYS} days.` };
        const upErr = await updateVenue(v.id, { field_sources: fs });
        if (upErr) console.error(`  provenance write failed for ${v.name}: ${upErr}`); else noneRecorded++;
      }
      continue;
    }

    withMenu++;
    const top = pickTopDrinks(ex.drinks, 6);
    const hhEnd = happyHourEnd(ex.happy_hour?.hours);
    console.log(`+ ${v.name}: ${ex.drinks.length} priced drinks` + (ex.happy_hour ? ` | HH ${ex.happy_hour.days ?? ""} ${ex.happy_hour.hours ?? ""} → ${hhEnd ?? "not one clock time, not written"}` : ""));
    for (const d of ex.drinks.slice(0, 6)) console.log(`     $${d.price.toFixed(2).padStart(6)}  ${d.category.padEnd(8)} ${d.name}`);

    if (!APPLY) continue;
    fs.popular_drinks = { source: "venue website menu", method: "llm_extract", model: MODEL, confidence: "high",
      at: today, date: today, fetched_at: fetchedAt, url: used[0], pages: used, items: ex.drinks,
      notes: `${ex.drinks.length} priced items extracted from the venue's own menu page(s); every price verified to appear verbatim in the page text (drink-menu-rules.priceAppearsInText). Full list: ${ex.drinks.map((d) => `${d.name} $${d.price}`).join("; ")}` };
    const patch: Record<string, unknown> = { popular_drinks: top };
    if (ex.happy_hour) {
      const hhProv: FieldSource = { source: "venue website", method: "llm_extract", model: MODEL, confidence: "medium",
        at: today, date: today, fetched_at: fetchedAt, url: used[0], happy_hour: ex.happy_hour,
        notes: `Site states: ${ex.happy_hour.days ?? ""} ${ex.happy_hour.hours ?? ""} — ${ex.happy_hour.deals ?? ""}`.trim() };
      const existingHuman = fs.happy_hour_until?.source && HUMAN_SOURCES.has(fs.happy_hour_until.source) && !FORCE;
      if (hhEnd && !existingHuman) {
        patch.happy_hour_until = hhEnd;
        fs.happy_hour_until = hhProv;
      } else if (!hhEnd && !v.happy_hour_until) {
        // The site states a happy hour but not one clock end time: keep the
        // verbatim window for a future days-aware column, write no value.
        fs.happy_hour_until = { ...hhProv, result: "window_not_single_clock_time" };
      }
    }
    patch.field_sources = fs;
    const upErr = await updateVenue(v.id, patch);
    if (upErr) console.error(`  write failed for ${v.name}: ${upErr}`); else written++;
  }
  console.log(`\nDone: ${withMenu}/${venues.length} venues had priced drink menus on their site${APPLY ? `, ${written} written, ${noneRecorded} recorded as none_published` : ""}.`);
}

main().catch((e) => { console.error(e); process.exit(1); });
