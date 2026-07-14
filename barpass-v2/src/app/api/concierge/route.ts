import { NextResponse } from "next/server";
import { GoogleGenAI } from "@google/genai";
import { getVenues } from "@/features/venues/services/venue-service";
import { buildConciergeSystemPrompt } from "@/features/ai/services/concierge-prompt";
import {
  conciergeRequestSchema,
  nightPlanSchema,
} from "@/features/ai/services/plan-schema";

/**
 * POST /api/concierge
 * Body: { prompt: string }
 * Returns: NightPlan JSON validated against nightPlanSchema.
 *
 * Gemini Flash (free tier at Google AI Studio) — the key lives ONLY here
 * (server-side). The client never talks to the model directly.
 */
export async function POST(request: Request) {
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

  try {
    const response = await ai.models.generateContent({
      model: "gemini-2.5-flash",
      contents: [{ role: "user", parts: [{ text: parsed.data.prompt }] }],
      config: {
        systemInstruction: buildConciergeSystemPrompt(venues),
        responseMimeType: "application/json",
        temperature: 0.9,
      },
    });

    const raw = response.text ?? "{}";
    const plan = nightPlanSchema.safeParse(JSON.parse(raw));

    if (!plan.success) {
      return NextResponse.json({ error: "invalid_plan" }, { status: 502 });
    }

    return NextResponse.json(plan.data);
  } catch {
    return NextResponse.json({ error: "ai_unavailable" }, { status: 502 });
  }
}
