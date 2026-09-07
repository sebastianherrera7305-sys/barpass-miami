/**
 * Concierge eval — runs a fixed set of real user prompts against a live
 * /api/concierge and grades each reply on what actually matters to a user
 * at a club at 1 AM:
 *
 *   latency   first user-facing byte, total
 *   language  reply language matches the prompt language
 *   grounded  every plan stop's venueId is a real catalog UUID
 *   open      every stop is open at its own "time"
 *   shape     plan block parses + validates (nightPlanSchema), or the reply
 *             is a question with an options block
 *   markdown  no bold markers or heading marks (the iOS bubble renders plain text)
 *
 * Usage: npm run eval:concierge [-- https://barpass-v2.vercel.app]
 * Prints a table + an overall score so a prompt/model change can be judged
 * against the previous run instead of by vibes.
 */
import { createClient } from "@supabase/supabase-js";
// @ts-ignore — ws ships no types here; same shim every other script uses for Node 20 realtime.
import ws from "ws";
import { nightPlanSchema } from "../src/features/ai/services/plan-schema";

const BASE = process.argv[2] ?? "https://barpass-v2.vercel.app";
const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;

interface Case { prompt: string; lang: "es" | "en"; city?: string; context?: Record<string, unknown>; expectPlan: boolean }

const CASES: Case[] = [
  { prompt: "Estoy en Factory Town esta noche, ¿qué me recomiendas después? algo cerca para seguir", lang: "es", expectPlan: true,
    context: { currentVenueId: "dfeef7e2-509a-42be-a72d-01a087e07e47" } },
  { prompt: "Plan a chill first date in Brickell tonight, $100 for two", lang: "en", expectPlan: true },
  { prompt: "Dónde hay reggaetón en Wynwood hoy, somos 5", lang: "es", expectPlan: true },
  { prompt: "plan something", lang: "en", expectPlan: false },
  { prompt: "Rooftop con vista para un cumpleaños, presupuesto $60 por persona", lang: "es", expectPlan: true },
  { prompt: "Can you get me an Uber to LIV?", lang: "en", expectPlan: false },
];

const ES_MARKERS = /\b(que|para|noche|donde|dónde|con|los|las|una|esta|pide|llega|vamos)\b/gi;
const EN_MARKERS = /\b(the|and|with|tonight|order|arrive|get|you|your|then|before)\b/gi;

function detectLang(text: string): "es" | "en" {
  const es = (text.match(ES_MARKERS) ?? []).length;
  const en = (text.match(EN_MARKERS) ?? []).length;
  return es >= en ? "es" : "en";
}

function toMinutes(t: string): number | null {
  const m = t.trim().match(/^(\d{1,2})(?::(\d{2}))?\s*(AM|PM|am|pm)?$/);
  if (!m) return null;
  let h = parseInt(m[1], 10);
  const min = m[2] ? parseInt(m[2], 10) : 0;
  const ap = m[3]?.toUpperCase();
  if (ap === "PM" && h < 12) h += 12;
  if (ap === "AM" && h === 12) h = 0;
  return h * 60 + min;
}

/** Is `at` inside [open, close) where close may wrap past midnight. */
function openAt(at: number, open: string, close: string): boolean {
  const o = toMinutes(open.replace(/^(\d{2}):(\d{2})$/, "$1:$2"));
  const c = toMinutes(close.replace(/^(\d{2}):(\d{2})$/, "$1:$2"));
  if (o === null || c === null) return true; // unknown hours → don't penalize
  if (o === c) return true;
  if (c > o) return at >= o && at < c;
  return at >= o || at < c; // wraps midnight
}

async function main() {
  const supabase = createClient(SUPABASE_URL, SUPABASE_KEY, { realtime: { transport: ws as unknown as typeof WebSocket } });
  const { data: venues, error } = await supabase
    .from("venues").select("id,name,open_time,close_time").eq("city", "Miami");
  if (error) throw error;
  const byId = new Map((venues ?? []).map((v) => [v.id as string, v]));

  let score = 0, max = 0;
  const rows: string[] = [];
  for (const c of CASES) {
    const t0 = Date.now();
    const res = await fetch(`${BASE}/api/concierge`, {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ city: c.city ?? "Miami", messages: [{ role: "user", content: c.prompt }], ...(c.context ? { context: c.context } : {}) }),
    });
    const provider = res.headers.get("x-bp-provider") ?? "?";
    const reader = res.body!.getReader();
    let firstContentMs: number | null = null;
    let raw = "";
    const dec = new TextDecoder();
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      const chunk = dec.decode(value, { stream: true });
      if (firstContentMs === null && chunk.includes("\x02")) firstContentMs = Date.now() - t0;
      raw += chunk;
    }
    const totalMs = Date.now() - t0;
    const text = raw.replace(/[\x01\x02]/g, "");

    const checks: Record<string, boolean> = {};
    checks.language = detectLang(text.replace(/```[\s\S]*?```/g, "")) === c.lang;
    checks.markdown = !/\*\*|^#+\s/m.test(text);
    const planMatch = text.match(/```json\s*([\s\S]*?)```/);
    const optMatch = /```options\s*\[[\s\S]*?\]\s*```/.test(text);
    if (c.expectPlan) {
      let plan: ReturnType<typeof nightPlanSchema.safeParse> | null = null;
      try { plan = planMatch ? nightPlanSchema.safeParse(JSON.parse(planMatch[1])) : null; } catch { plan = null; }
      checks.shape = !!plan?.success;
      if (plan?.success) {
        checks.grounded = plan.data.stops.every((s) => s.venueId && byId.has(s.venueId));
        checks.open = plan.data.stops.every((s) => {
          const v = s.venueId ? byId.get(s.venueId) : undefined;
          const at = toMinutes(s.time);
          return !v || at === null || openAt(at, v.open_time, v.close_time);
        });
      } else { checks.grounded = false; checks.open = false; }
    } else {
      checks.shape = !planMatch && (optMatch || text.length > 20);
    }
    checks.fast = (firstContentMs ?? 99999) < 6000 && totalMs < 20000;

    const passed = Object.values(checks).filter(Boolean).length;
    score += passed; max += Object.keys(checks).length;
    rows.push(
      `${c.prompt.slice(0, 44).padEnd(46)} ${provider.padEnd(12)} first ${String(firstContentMs ?? "-").padStart(5)}ms total ${String(totalMs).padStart(6)}ms  ` +
      Object.entries(checks).map(([k, v]) => `${v ? "✓" : "✗"}${k}`).join(" "),
    );
    await new Promise((r) => setTimeout(r, 3000));
  }
  console.log(rows.join("\n"));
  console.log(`\nSCORE ${score}/${max} (${Math.round((100 * score) / max)}%) against ${BASE}`);
}

main().catch((e) => { console.error(e); process.exit(1); });
