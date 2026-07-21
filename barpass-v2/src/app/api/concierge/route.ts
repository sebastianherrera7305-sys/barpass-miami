import { NextResponse } from "next/server";
import { GoogleGenAI } from "@google/genai";
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
 * Gemini Flash (free tier at Google AI Studio) — the key lives ONLY here
 * (server-side). The client never talks to the model directly.
 *
 * SECURITY (Pre-Launch Audit, Phase 1 #6): this route had no rate limiting
 * at all — harmless only because GEMINI_API_KEY isn't set yet (every call
 * 503s). Rate-limited by IP rather than gated behind auth: the Concierge is
 * a guest-accessible feature today (no login wall anywhere else in its
 * flow), so requiring auth here would be a product change, not a security
 * fix — this closes the actual gap (unauthenticated cost/DoS abuse of the
 * AI budget) without silently login-walling a feature that never had one.
 */
export async function POST(request: Request) {
  const ip = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "unknown";
  // 10 requests/minuto por IP — cubre uso normal (varios intentos de prompt
  // en una sesión), frena abuso automatizado del presupuesto de Gemini.
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

  if (!process.env.GEMINI_API_KEY) {
    return NextResponse.json({ error: "ai_not_configured" }, { status: 503 });
  }

  const venues = await getVenues();
  const ai = new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY });
  const systemInstruction = buildConciergeSystemPrompt(venues, {
    excludeSlugs: parsed.data.excludeSlugs,
  });

  // Un reintento — el modelo ocasionalmente devuelve JSON corrupto (glitch
  // de generación, no truncamiento: eso ya se resolvió con maxOutputTokens/
  // thinkingConfig abajo). Antes esto era un error inmediato al usuario por
  // algo que una segunda llamada normalmente resuelve solo.
  for (let attempt = 1; attempt <= 2; attempt++) {
    try {
      const response = await ai.models.generateContent({
        // Alias en vez de una versión fija — "gemini-2.5-flash" quedó
        // descontinuado por Google para API keys nuevas ("no longer
        // available to new users", error 404) y rompía el Concierge en
        // silencio. "-latest" apunta siempre al flash vigente.
        model: "gemini-flash-latest",
        contents: [{ role: "user", parts: [{ text: parsed.data.prompt }] }],
        config: {
          systemInstruction,
          responseMimeType: "application/json",
          temperature: 0.9,
          // Sin esto, un plan con muchos stops/notes largas se podía cortar
          // a mitad de generación y romper el JSON.parse — el default del
          // SDK es más chico de lo que este prompt necesita. Los modelos
          // Gemini 2.5 gastan parte del budget en "thinking" interno antes
          // de emitir texto visible, así que el límite tiene que ser generoso.
          maxOutputTokens: 8192,
          thinkingConfig: { thinkingBudget: 0 },
        },
      });

      const raw = response.text ?? "{}";
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
