import { NextResponse } from "next/server";
import { getVenues } from "@/features/venues/services/venue-service";
import { buildConciergeSystemPrompt } from "@/features/ai/services/concierge-prompt";
import {
  conciergeRequestSchema,
  nightPlanSchema,
} from "@/features/ai/services/plan-schema";
import { checkRateLimit } from "@/lib/rate-limit";

/**
 * POST /api/concierge
 * Body: { prompt: string }
 * Returns: NightPlan JSON validated against nightPlanSchema.
 *
 * NVIDIA NIM (OpenAI-compatible chat completions endpoint) — the key lives
 * ONLY here (server-side, NVIDIA_API_KEY), never in the client bundle.
 * Was Gemini Flash until this swap; same contract (system prompt in, one
 * JSON night-plan object out, validated below) so the rest of the app
 * (schema, prompt builder, client) needed zero changes.
 *
 * SECURITY (Pre-Launch Audit, Phase 1 #6): this route had no rate limiting
 * at all — harmless only because no key was set (every call 503'd). Rate-
 * limited by IP rather than gated behind auth: the Concierge is a guest-
 * accessible feature today (no login wall anywhere else in its flow), so
 * requiring auth here would be a product change, not a security fix — this
 * closes the actual gap (unauthenticated cost/DoS abuse of the AI budget)
 * without silently login-walling a feature that never had one.
 */
const NVIDIA_CHAT_URL = "https://integrate.api.nvidia.com/v1/chat/completions";
// Meta's Llama 3.3 70B on NVIDIA's hosted catalog — strong instruction
// following for a "return exactly this JSON shape" task, generally
// available (not a preview/limited-access model).
const NVIDIA_MODEL = "meta/llama-3.3-70b-instruct";

export async function POST(request: Request) {
  const ip = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "unknown";
  // 10 requests/minuto por IP — cubre uso normal (varios intentos de prompt
  // en una sesión), frena abuso automatizado del presupuesto de NVIDIA.
  const withinLimit = await checkRateLimit(`concierge:${ip}`, {
    maxRequests: 10,
    windowSeconds: 60,
  });
  if (!withinLimit) {
    return NextResponse.json({ error: "rate_limited" }, { status: 429 });
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }
  const parsed = conciergeRequestSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: "invalid_request" }, { status: 400 });
  }

  if (!process.env.NVIDIA_API_KEY) {
    return NextResponse.json({ error: "ai_not_configured" }, { status: 503 });
  }

  const venues = await getVenues();
  const systemInstruction = buildConciergeSystemPrompt(venues, {
    excludeSlugs: parsed.data.excludeSlugs,
  });

  // Un reintento — el modelo ocasionalmente devuelve JSON corrupto o con un
  // campo faltante (glitch de generación). Antes esto era un error inmediato
  // al usuario por algo que una segunda llamada normalmente resuelve solo.
  for (let attempt = 1; attempt <= 2; attempt++) {
    try {
      const response = await fetch(NVIDIA_CHAT_URL, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${process.env.NVIDIA_API_KEY}`,
          "Content-Type": "application/json",
          Accept: "application/json",
        },
        body: JSON.stringify({
          model: NVIDIA_MODEL,
          messages: [
            { role: "system", content: systemInstruction },
            { role: "user", content: parsed.data.prompt },
          ],
          temperature: 0.9,
          // Generoso por la misma razón que con Gemini — un plan con varios
          // stops y notas largas se corta a mitad de generación si el límite
          // es chico, y rompe el JSON.parse de abajo.
          max_tokens: 2048,
          response_format: { type: "json_object" },
        }),
      });

      if (!response.ok) {
        console.error(`Concierge NVIDIA call failed (attempt ${attempt}): HTTP ${response.status}`, await response.text());
        continue;
      }

      const completion = await response.json();
      const raw = completion.choices?.[0]?.message?.content ?? "{}";
      const parsedJson = JSON.parse(raw);
      const plan = nightPlanSchema.safeParse(parsedJson);

      if (!plan.success) {
        console.error(`Concierge JSON failed schema validation (attempt ${attempt}):`, plan.error.issues);
        continue;
      }

      return NextResponse.json(plan.data);
    } catch (e) {
      console.error(`Concierge call failed (attempt ${attempt}):`, e);
    }
  }

  return NextResponse.json({ error: "ai_unavailable" }, { status: 502 });
}
