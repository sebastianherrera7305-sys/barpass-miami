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
  htmlToText, menuLinks, menuAssets, hasPricedText, sanitizeDrinks, pickTopDrinks, happyHourEnd, extractionPrompt,
  type Extracted, type ExtractedDrink, type ExtractedHappyHour,
} from "./drink-menu-rules";

import dns from "node:dns";

// El resolver del sistema se ahoga con cientos de consultas seguidas: dos
// corridas se cortaron a mitad de ciudad con ENOTFOUND en sitios que estaban
// perfectos (facebook.com entre ellos). Cloudflare y Google aguantan este
// volumen sin pestañear, y `ipv4first` evita el camino AAAA que en esta red
// es el que más falla.
dns.setServers(["1.1.1.1", "8.8.8.8", "1.0.0.1"]);
dns.setDefaultResultOrder("ipv4first");

const args = process.argv.slice(2);
const flag = (n: string) => { const i = args.indexOf(n); return i === -1 ? undefined : args[i + 1]; };
/** The vision pass costs a model call per image, so it can be turned off for a
 *  cheap text-only sweep. On by default: without it the hit rate in a college
 *  town was 1 in 12. */
const USE_VISION = !args.includes("--no-vision");

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
  --no-vision          skip reading menus published as images/PDFs (cheaper, much lower hit rate)
  --help               this text

Env (from .env.local): NEXT_PUBLIC_SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, NVIDIA_API_KEY, GEMINI_API_KEY (vision)`);
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
    // Full browser-shaped headers: several venue hosts answer 403 to a bare
    // User-Agent (balls.poi.place did, in the Gainesville pilot).
    const res = await fetchWithDnsRetry(url, ctrl.signal);
    return await handleResponse(res);
  } catch (e) {
    lastFetchError = e instanceof Error && e.name === "AbortError" ? `timeout after ${ms / 1000}s` : `${e instanceof Error ? e.cause instanceof Error ? e.cause.message : e.message : e}`;
    return null;
  } finally { clearTimeout(t); }
}

/** Un ENOTFOUND aislado casi siempre es el resolver, no el dominio: se
 *  reintenta una vez después de un respiro antes de darlo por caído. */
async function fetchWithDnsRetry(url: string, signal: AbortSignal): Promise<Response> {
  try {
    return await rawFetch(url, signal);
  } catch (e) {
    const msg = e instanceof Error ? (e.cause instanceof Error ? e.cause.message : e.message) : String(e);
    if (!/ENOTFOUND|EAI_AGAIN/i.test(msg)) throw e;
    await sleep(1200);
    return await rawFetch(url, signal);
  }
}

async function rawFetch(url: string, signal: AbortSignal): Promise<Response> {
    const res = await fetch(url, { headers: {
      "User-Agent": UA,
      Accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      "Accept-Language": "en-US,en;q=0.9",
      "Sec-Fetch-Dest": "document", "Sec-Fetch-Mode": "navigate", "Sec-Fetch-Site": "none",
      "Upgrade-Insecure-Requests": "1",
    }, signal, redirect: "follow" });
  return res;
}

function handleResponse(res: Response): Promise<{ html: string; finalUrl: string } | null> {
  if (!res.ok) { lastFetchError = `HTTP ${res.status}`; return Promise.resolve(null); }
  const ct = res.headers.get("content-type") ?? "";
  if (!ct.includes("html")) { lastFetchError = `not HTML (${ct.split(";")[0] || "no content-type"})`; return Promise.resolve(null); }
  return res.text().then((html) => ({ html, finalUrl: res.url }));
}

/** The vision pass: read the menu a venue published as a picture.
 *
 * Measured 2026-09-16 on Boxcar (Gainesville), whose entire drink list is a
 * JPG: the text pipeline returned nothing, this returned 24 priced drinks.
 *
 * The model is asked for a verbatim transcription ALONGSIDE the structured
 * items, and the same sanitizer then checks every price against that
 * transcription — the identical invariant the HTML path uses, with the
 * model's own reading of the image standing in for the page text. The
 * transcription is stored in provenance so a human can audit any price
 * without re-downloading the image.
 */
const VISION_MODEL = "gemini-3.6-flash";
/** 20 requests/minute on the free tier → one every 3.5s, with room to spare. */
const VISION_PACE_MS = 3500;
let lastVisionCallAt = 0;
const GEMINI_KEY = process.env.GEMINI_API_KEY;
const MAX_ASSET_BYTES = 8 * 1024 * 1024;

async function fetchAsset(url: string): Promise<{ b64: string; mime: string } | null> {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), 20000);
  try {
    const res = await fetch(url, { headers: { "User-Agent": UA }, signal: ctrl.signal, redirect: "follow" });
    if (!res.ok) return null;
    const mime = (res.headers.get("content-type") ?? "").split(";")[0].trim();
    if (!/^(image\/(jpeg|png|webp)|application\/pdf)$/.test(mime)) return null;
    const buf = Buffer.from(await res.arrayBuffer());
    if (buf.byteLength > MAX_ASSET_BYTES || buf.byteLength < 1024) return null;
    return { b64: buf.toString("base64"), mime };
  } catch { return null; } finally { clearTimeout(t); }
}

/** Set when a vision call could not be MADE (quota, network, bad asset) — as
 *  opposed to being made and finding no priced drinks. The difference decides
 *  whether we may write "this venue publishes no prices", and getting it wrong
 *  is how a run on 2026-09-16 recorded that lie about venues whose menu image
 *  was never read: the free Gemini tier allows 20 requests a minute and the
 *  sweep burned through it. */
let visionUnavailable = false;

async function visionExtract(venue: DbVenue, assetUrl: string): Promise<{ drinks: ExtractedDrink[]; transcript: string } | null> {
  if (!GEMINI_KEY) { visionUnavailable = true; return null; }
  const asset = await fetchAsset(assetUrl);
  if (!asset) return null;
  // Stay under the free tier's 20 requests/minute instead of discovering it
  // through a wall of 429s.
  const since = Date.now() - lastVisionCallAt;
  if (since < VISION_PACE_MS) await sleep(VISION_PACE_MS - since);
  lastVisionCallAt = Date.now();
  const prompt = [
    `This is a menu published by "${venue.name}" (${venue.city}).`,
    "Return ONLY JSON, no prose, no code fence:",
    '{"transcript":"every line of text you can read, verbatim, including the prices","drinks":[{"name":"...","price":0.00,"category":"cocktail|beer|wine|shot|spirit|other"}]}',
    "Rules: include a drink ONLY if a price is printed next to it on this image.",
    "Never guess or round a price. No food. If the image is not a drink menu, return an empty drinks array.",
  ].join("\n");
  const body = JSON.stringify({
    contents: [{ parts: [{ text: prompt }, { inline_data: { mime_type: asset.mime, data: asset.b64 } }] }],
    generationConfig: { temperature: 0 },
  });
  // A 503 here is transient and expensive to ignore: the first Gainesville
  // run lost Boxcar's 24-item menu to one, fell through to a smaller image,
  // and recorded 6 drinks as if that were the whole card.
  for (let attempt = 1; attempt <= 4; attempt++) {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), 180000);
    try {
      const res = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${VISION_MODEL}:generateContent`,
        { method: "POST", headers: { "Content-Type": "application/json", "x-goog-api-key": GEMINI_KEY }, body, signal: ctrl.signal });
      if (res.status === 429 || res.status >= 500) {
        // Google tells us exactly how long to wait ("Please retry in 18.2s") —
        // use it instead of guessing.
        const bodyText = await res.text().catch(() => "");
        const told = Number(/retry in ([\d.]+)s/i.exec(bodyText)?.[1] ?? 0) * 1000;
        const wait = Math.max(told + 1500, 8000 * attempt);
        console.error(`  vision HTTP ${res.status} — attempt ${attempt}/4, waiting ${Math.round(wait / 1000)}s`);
        if (attempt < 4) { await sleep(wait); continue; }
        visionUnavailable = true;
        return null;
      }
      if (!res.ok) { console.error(`  vision HTTP ${res.status} on ${assetUrl}`); visionUnavailable = true; return null; }
      const data = await res.json() as { candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }> };
      const raw = data.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
      const json = raw.replace(/^```(?:json)?/i, "").replace(/```$/, "").trim();
      const parsed = JSON.parse(json) as { transcript?: string; drinks?: unknown };
      const transcript = typeof parsed.transcript === "string" ? parsed.transcript : "";
      // Same gate as the HTML path: a price that isn't in the text we read is dropped.
      return { drinks: sanitizeDrinks(parsed.drinks, transcript), transcript };
    } catch (e) {
      console.error(`  vision failed on ${assetUrl}: ${e instanceof Error ? e.message : e}`);
      visionUnavailable = true;
      return null;
    } finally { clearTimeout(t); }
  }
  return null;
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

  let withMenu = 0, written = 0, noneRecorded = 0, viaVision = 0;
  // A run on 2026-09-16 lost its DNS half-way through Gainesville and marched
  // on, printing "site unreachable" for 45 venues in a row — including
  // facebook.com and olivegarden.com, which are plainly fine. That is OUR
  // network failing, not theirs, and a sweep that keeps going produces a
  // city's worth of false negatives. Stop instead, and say so.
  let consecutiveNetworkFailures = 0;
  for (const v of venues) {
    const home = await fetchText(v.website!);
    if (!home) {
      console.log(`- ${v.name}: site unreachable (${lastFetchError}) ${v.website}`);
      if (/ENOTFOUND|EAI_AGAIN|ECONNREFUSED|ETIMEDOUT|fetch failed/i.test(lastFetchError)) {
        if (++consecutiveNetworkFailures >= 5) {
          console.error(`\nSTOPPING: ${consecutiveNetworkFailures} network failures in a row — this machine lost DNS or connectivity, the sites are probably fine.`);
          console.error("Nothing was recorded for them. Re-run when the network is back; venues already done are skipped.");
          break;
        }
      } else consecutiveNetworkFailures = 0;
      continue;
    }
    consecutiveNetworkFailures = 0;
    const links = menuLinks(home.html, home.finalUrl, MAX_PAGES - 1);
    // Menu pages first, the home page last: the model reads a bounded slice
    // of this text, and a home page rarely holds the drink list.
    const pages = [...links.filter((l) => l !== home.finalUrl), home.finalUrl].slice(-MAX_PAGES);
    let text = "";
    const used: string[] = [];
    // Kept for the vision pass: the menu is often a picture ON one of these
    // pages, and by then the HTML is gone if we only keep the text.
    const readPages: Array<{ url: string; html: string }> = [];
    for (const url of pages) {
      const page = url === home.finalUrl ? home : await fetchText(url);
      if (!page) continue;
      readPages.push({ url: page.finalUrl, html: page.html });
      const t = htmlToText(page.html);
      if (hasPricedText(t)) { text += `\n\n[${url}]\n${t}`; used.push(url); }
    }
    const fetchedAt = new Date().toISOString();
    const today = fetchedAt.slice(0, 10);
    const fs = { ...(v.field_sources ?? {}) } as Record<string, FieldSource | undefined>;

    const ex = hasPricedText(text) ? await extract(v, text) : { drinks: [], happy_hour: null };
    if (!ex) { console.log(`- ${v.name}: model call failed (nothing recorded)`); continue; }

    // The text path found nothing. Before writing this venue off, look for a
    // menu published as an image or PDF — which is what most bars actually do.
    let visionHit: { drinks: ExtractedDrink[]; transcript: string; url: string } | null = null;
    visionUnavailable = false;
    let hadAssets = false;
    if (ex.drinks.length === 0 && USE_VISION && GEMINI_KEY) {
      const assets = readPages.flatMap((p) => menuAssets(p.html, p.url, 2)).slice(0, 3);
      hadAssets = assets.length > 0;
      for (const asset of assets) {
        const got = await visionExtract(v, asset);
        if (got && got.drinks.length > 0) { visionHit = { ...got, url: asset }; break; }
      }
    }

    if (ex.drinks.length === 0 && !visionHit) {
      console.log(`- ${v.name}: ${used.length === 0 ? `no priced text on site (${pages.length} pages)` : "prices on site but no verifiable drink items"}`);
      // Record the finding so the venue is not re-crawled next run — unless it
      // already has drinks (a --force re-check that found nothing keeps them),
      // or unless the venue publishes a menu image we were never able to read.
      // "We ran out of quota" is not evidence that a bar publishes no prices.
      if (hadAssets && visionUnavailable) {
        console.log(`  ↳ ${v.name} publishes a menu image we could not read (quota/transport) — nothing recorded, will retry`);
        continue;
      }
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
    if (visionHit) {
      viaVision++;
      ex.drinks = visionHit.drinks;
    }
    const top = pickTopDrinks(ex.drinks, 6);
    const hhEnd = happyHourEnd(ex.happy_hour?.hours);
    console.log(`+ ${v.name}: ${ex.drinks.length} priced drinks${visionHit ? " (from the menu image)" : ""}` + (ex.happy_hour ? ` | HH ${ex.happy_hour.days ?? ""} ${ex.happy_hour.hours ?? ""} → ${hhEnd ?? "not one clock time, not written"}` : ""));
    for (const d of ex.drinks.slice(0, 6)) console.log(`     $${d.price.toFixed(2).padStart(6)}  ${d.category.padEnd(8)} ${d.name}`);

    if (!APPLY) continue;
    fs.popular_drinks = visionHit
      ? { source: "venue menu image", method: "vision_extract", model: VISION_MODEL, confidence: "high",
          at: today, date: today, fetched_at: fetchedAt, url: visionHit.url, pages: [visionHit.url], items: ex.drinks,
          notes: `${ex.drinks.length} priced items read from the menu image the venue publishes; every price verified against the model's own verbatim transcription of that image. Transcript: ${visionHit.transcript.slice(0, 1500)}` }
      : { source: "venue website menu", method: "llm_extract", model: MODEL, confidence: "high",
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
  console.log(`\nDone: ${withMenu}/${venues.length} venues had priced drink menus (${viaVision} readable only as an image)${APPLY ? `, ${written} written, ${noneRecorded} recorded as none_published` : ""}.`);
}

main().catch((e) => { console.error(e); process.exit(1); });
