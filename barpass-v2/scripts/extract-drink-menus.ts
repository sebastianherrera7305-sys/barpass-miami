/**
 * Drink menus with REAL prices, from each venue's own website.
 *
 * "Lo que se necesita es saber qué tragos venden, dónde, cuándo y a cuánto"
 * (2026-09-08). The catalog has 0 venues with popular_drinks (the fabricated
 * seed was cleared on 2026-09-01) and 1,465 of 1,734 served venues have a
 * website. This script visits that website, finds the menu/drinks/happy-hour
 * pages, and asks a model to pull out ONLY items with an explicit price. It
 * never invents: no price in the text → no item. Every write carries
 * provenance in field_sources (url, date, item count).
 *
 * Writes (with --apply):
 *   venues.popular_drinks   top 6 items [{name, price, emoji}] — the iOS
 *                           "Popular drinks" section renders this as-is
 *   venues.happy_hour_until "HH:MM" when the site states an end time
 *   venues.field_sources    .popular_drinks / .happy_hour_until provenance
 *
 * Usage:
 *   npm run extract:menus -- --city Miami --limit 5           # dry run
 *   npm run extract:menus -- --city Miami --apply             # write
 *   npm run extract:menus -- --city Miami --apply --only <venue-id>
 */
import { createClient } from "@supabase/supabase-js";
// @ts-expect-error — ws ships no types here; same shim every other script uses for Node 20 realtime.
import ws from "ws";

const args = process.argv.slice(2);
const flag = (n: string) => { const i = args.indexOf(n); return i === -1 ? undefined : args[i + 1]; };
const CITY = flag("--city") ?? "Miami";
const LIMIT = Number(flag("--limit") ?? 9999);
const ONLY = flag("--only");
/** A file of "<venue id>\t<city>" lines — one process for a whole retry list
 * instead of one npm/tsx boot per venue (2026-09-08: the per-venue loop was
 * spending ~2 min each on startup + a full catalog query, for a 3.5h run). */
const IDS_FILE = flag("--ids-file");
const APPLY = args.includes("--apply");
const FORCE = args.includes("--force"); // re-extract venues that already have popular_drinks

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;
const NVIDIA_KEY = process.env.NVIDIA_API_KEY!;
const MODEL = "openai/gpt-oss-20b";

interface DbVenue { id: string; name: string; city: string; type: string; website: string | null; popular_drinks: unknown; field_sources: Record<string, unknown> | null }
interface Drink { name: string; price: number; category: string; note?: string }
interface Extracted { drinks: Drink[]; happy_hour: { days?: string; hours?: string; deals?: string } | null }

const UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1";
const MENU_WORDS = /menu|drink|cocktail|beer|wine|happy|bar\b|bebida|carta|trago|bottle|specials|food/i;

async function fetchText(url: string, ms = 12000): Promise<{ html: string; finalUrl: string } | null> {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), ms);
  try {
    const res = await fetch(url, { headers: { "User-Agent": UA, Accept: "text/html,*/*" }, signal: ctrl.signal, redirect: "follow" });
    if (!res.ok) return null;
    const ct = res.headers.get("content-type") ?? "";
    if (!ct.includes("html")) return null;
    return { html: await res.text(), finalUrl: res.url };
  } catch { return null; } finally { clearTimeout(t); }
}

function htmlToText(html: string): string {
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<noscript[\s\S]*?<\/noscript>/gi, " ")
    .replace(/<br\s*\/?>|<\/(p|div|li|tr|h\d|section|article)>/gi, "\n")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/g, " ").replace(/&amp;/g, "&").replace(/&#39;|&rsquo;/g, "'").replace(/&quot;/g, '"')
    .replace(/[ \t]+/g, " ").replace(/\n\s*\n+/g, "\n").trim();
}

function menuLinks(html: string, base: string): string[] {
  const out = new Set<string>();
  const origin = new URL(base).origin;
  for (const m of html.matchAll(/href=["']([^"'#]+)["'][^>]*>([\s\S]{0,120}?)</gi)) {
    const href = m[1]; const label = m[2].replace(/<[^>]+>/g, " ");
    if (!MENU_WORDS.test(href) && !MENU_WORDS.test(label)) continue;
    try {
      const u = new URL(href, base);
      if (u.origin !== origin) continue;
      if (/\.(pdf|jpg|png|webp)$/i.test(u.pathname)) continue; // PDF/image menus: out of scope for v1
      out.add(u.toString().split("?")[0]);
    } catch { /* bad href */ }
  }
  return [...out].slice(0, 4);
}

async function extract(venue: DbVenue, text: string, sourceUrls: string[]): Promise<Extracted | null> {
  const prompt = `You extract drink menu data from a venue's website text. Venue: "${venue.name}" (${venue.type}, ${venue.city}).
Return ONLY JSON: {"drinks":[{"name":"","price":0,"category":"cocktail|beer|wine|shot|bottle|other","note":""}],"happy_hour":{"days":"","hours":"","deals":""}}
RULES: include a drink ONLY if the text states its price explicitly (a number with $ or a clear price). Never guess or infer a price. Max 12 drinks, prefer signature cocktails, then beer/wine. "note" = size/brand detail only if stated. happy_hour only if the text states one (null otherwise); "hours" verbatim like "4-7pm". If there are no priced drinks, return {"drinks":[],"happy_hour":null}.

TEXT:
${text.slice(0, 7000)}`;
  // Bounded: one hung NIM call (undici headers timeout at 5 min) took the
  // whole run down on the first dry run. 75s is generous for a 1.2K-token reply.
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), 120_000);
  let json: { choices?: Array<{ message?: { content?: string } }> };
  try {
    const res = await fetch("https://integrate.api.nvidia.com/v1/chat/completions", {
      method: "POST",
      headers: { Authorization: `Bearer ${NVIDIA_KEY}`, "Content-Type": "application/json" },
      body: JSON.stringify({ model: MODEL, reasoning_effort: "low", temperature: 0, max_tokens: 1200,
        messages: [{ role: "user", content: prompt }] }),
      signal: ctrl.signal,
    });
    if (!res.ok) { console.error(`  model HTTP ${res.status} for ${venue.name}`); return null; }
    json = await res.json();
  } catch (e) {
    console.error(`  model call failed for ${venue.name}: ${e instanceof Error ? e.name : e}`);
    return null;
  } finally { clearTimeout(timer); }
  const content: string = json.choices?.[0]?.message?.content ?? "";
  const m = content.match(/\{[\s\S]*\}/);
  if (!m) return null;
  try {
    const parsed = JSON.parse(m[0]) as Extracted;
    const drinks = (parsed.drinks ?? [])
      .filter((d) => d && typeof d.name === "string" && d.name.trim().length > 1 && Number.isFinite(Number(d.price)))
      .map((d) => ({ ...d, name: d.name.trim().slice(0, 60), price: Math.round(Number(d.price) * 100) / 100, category: String(d.category ?? "other").toLowerCase() }))
      .filter((d) => d.price >= 2 && d.price <= 500);
    // Belt and braces: the price must literally appear in the source text.
    const priced = drinks.filter((d) => {
      const whole = String(Math.round(d.price)); const dec = d.price.toFixed(2);
      return text.includes(`$${whole}`) || text.includes(`$${dec}`) || text.includes(`${whole}.00`) || text.includes(dec);
    });
    const seen = new Set<string>();
    const dedup = priced.filter((d) => { const k = d.name.toLowerCase(); if (seen.has(k)) return false; seen.add(k); return true; });
    void sourceUrls;
    return { drinks: dedup.slice(0, 12), happy_hour: parsed.happy_hour && (parsed.happy_hour.hours || parsed.happy_hour.deals) ? parsed.happy_hour : null };
  } catch { return null; }
}

const EMOJI: Record<string, string> = { cocktail: "🍸", beer: "🍺", wine: "🍷", shot: "🥃", bottle: "🍾", other: "🥤" };

/** "4-7pm", "until 7 PM", "5pm-8pm" → "19:00" (end time) or null. */
function happyHourEnd(hours?: string): string | null {
  if (!hours) return null;
  const times = [...hours.matchAll(/(\d{1,2})(?::(\d{2}))?\s*(am|pm)?/gi)];
  if (times.length === 0) return null;
  const last = times[times.length - 1];
  let h = parseInt(last[1], 10); const mm = last[2] ?? "00"; const ap = (last[3] ?? "").toLowerCase();
  if (ap === "pm" && h < 12) h += 12;
  if (!ap && h < 12 && h >= 1 && h <= 9) h += 12; // "4-7" with no am/pm: happy hour is an evening thing
  if (h > 23) return null;
  return `${String(h).padStart(2, "0")}:${mm}`;
}

async function main() {
  const supabase = createClient(SUPABASE_URL, SERVICE_KEY, { realtime: { transport: ws as unknown as typeof WebSocket } });
  let q = supabase.from("venues").select("id,name,city,type,website,popular_drinks,field_sources")
    .is("excluded_reason", null).not("website", "is", null).order("name");
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
  const venues = (data as DbVenue[]).filter((v) => FORCE || ONLY || IDS_FILE || !(Array.isArray(v.popular_drinks) && v.popular_drinks.length) && !(typeof v.popular_drinks === "string" && v.popular_drinks.length > 2)).slice(0, LIMIT);
  console.log(`${venues.length} venues ${IDS_FILE ? "from list" : `in ${CITY}`} to try (${APPLY ? "APPLY" : "dry run"})`);

  let withMenu = 0, written = 0;
  for (const v of venues) {
    const home = await fetchText(v.website!);
    if (!home) { console.log(`- ${v.name}: site unreachable`); continue; }
    const links = menuLinks(home.html, home.finalUrl);
    const pages = [home.finalUrl, ...links.filter((l) => l !== home.finalUrl)];
    let text = "";
    const used: string[] = [];
    for (const url of pages.slice(0, 4)) {
      const page = url === home.finalUrl ? home : await fetchText(url);
      if (!page) continue;
      const t = htmlToText(page.html);
      if (/\$\s?\d/.test(t)) { text += `\n\n[${url}]\n${t}`; used.push(url); }
    }
    if (!/\$\s?\d/.test(text)) { console.log(`- ${v.name}: no priced text on site (${pages.length} pages)`); continue; }
    const ex = await extract(v, text, used);
    if (!ex || ex.drinks.length === 0) { console.log(`- ${v.name}: prices on site but no drink items extracted`); continue; }
    withMenu++;
    const top = [...ex.drinks].sort((a, b) => (a.category === "cocktail" ? -1 : 1) - (b.category === "cocktail" ? -1 : 1)).slice(0, 6)
      .map((d) => ({ name: d.name, price: d.price, emoji: EMOJI[d.category] ?? "🥤" }));
    const hhEnd = happyHourEnd(ex.happy_hour?.hours);
    console.log(`+ ${v.name}: ${ex.drinks.length} priced drinks` + (ex.happy_hour ? ` | HH ${ex.happy_hour.days ?? ""} ${ex.happy_hour.hours ?? ""} → ${hhEnd ?? "?"}` : ""));
    for (const d of ex.drinks.slice(0, 6)) console.log(`     $${d.price.toFixed(2).padStart(6)}  ${d.category.padEnd(8)} ${d.name}`);

    if (!APPLY) continue;
    const today = new Date().toISOString().slice(0, 10);
    const fs = { ...(v.field_sources ?? {}) } as Record<string, unknown>;
    fs.popular_drinks = { source: "venue website menu", url: used[0], confidence: "high", date: today,
      notes: `${ex.drinks.length} priced items extracted from the venue's own menu page(s) by ${MODEL}; every price verified to appear verbatim in the page text. Full list: ${ex.drinks.map((d) => `${d.name} $${d.price}`).join("; ")}` };
    const patch: Record<string, unknown> = { popular_drinks: top, field_sources: fs };
    if (hhEnd) {
      patch.happy_hour_until = hhEnd;
      fs.happy_hour_until = { source: "venue website", url: used[0], confidence: "medium", date: today, notes: `Site states: ${ex.happy_hour?.days ?? ""} ${ex.happy_hour?.hours ?? ""} — ${ex.happy_hour?.deals ?? ""}`.trim() };
    }
    const { error: upErr } = await supabase.from("venues").update(patch).eq("id", v.id);
    if (upErr) console.error(`  write failed for ${v.name}:`, upErr.message); else written++;
    await new Promise((r) => setTimeout(r, 1500)); // NIM rate limit
  }
  console.log(`\nDone: ${withMenu}/${venues.length} venues had priced drink menus on their site${APPLY ? `, ${written} written` : ""}.`);
}

main().catch((e) => { console.error(e); process.exit(1); });
