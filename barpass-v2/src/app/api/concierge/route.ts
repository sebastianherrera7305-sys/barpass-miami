import { NextResponse } from "next/server";
import OpenAI from "openai";
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
 * The OpenAI key lives ONLY here (server-side). The client never talks to
 * the model directly.
 */
export async function POST(request: Request) {
  const parsed = conciergeRequestSchema.safeParse(await request.json());
  if (!parsed.success) {
    return NextResponse.json({ error: "invalid_request" }, { status: 400 });
  }

  if (!process.env.OPENAI_API_KEY) {
    return NextResponse.json({ error: "ai_not_configured" }, { status: 503 });
  }

  const venues = await getVenues();
  const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

  try {
    const completion = await openai.chat.completions.create({
      model: "gpt-4o-mini",
      response_format: { type: "json_object" },
      temperature: 0.8,
      messages: [
        { role: "system", content: buildConciergeSystemPrompt(venues) },
        { role: "user", content: parsed.data.prompt },
      ],
    });

    const raw = completion.choices[0]?.message?.content ?? "{}";
    const plan = nightPlanSchema.safeParse(JSON.parse(raw));

    if (!plan.success) {
      return NextResponse.json({ error: "invalid_plan" }, { status: 502 });
    }

    return NextResponse.json(plan.data);
  } catch {
    return NextResponse.json({ error: "ai_unavailable" }, { status: 502 });
  }
}
