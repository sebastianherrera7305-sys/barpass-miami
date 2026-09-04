import { getVenues } from "@/features/venues/services/venue-service";
import { buildConciergeSystemPrompt, selectRelevantVenues } from "@/features/ai/services/concierge-prompt";
import { conciergeChatRequestSchema } from "@/features/ai/services/plan-schema";
import { checkRateLimit } from "@/lib/rate-limit";

/**
 * POST /api/concierge
 * Body: { messages: [{role, content}], city? }
 * Returns: a raw text/plain STREAM of Remy's reply as it's generated —
 * this is a real chat now, not a single request/response plan generator.
 * A message may end in a ```json ... ``` fenced NightPlan block; the
 * client is responsible for detecting and rendering that block as a card
 * (see plan-schema.ts's nightPlanSchema for what's inside it).
 *
 * Two OpenAI-compatible providers, both streaming — keys live ONLY here
 * (server-side), never in the client bundle:
 *
 * - Groq (preferred, when GROQ_API_KEY is set): custom LPU hardware, ~120ms
 *   time-to-first-token and 500-1000+ tok/s. llama-3.3-70b-versatile is NOT
 *   a reasoning model, so there's no 20-30s "thinking" delay before the
 *   real answer starts — this is the actual fix for Remy feeling slow, not
 *   just perceived-slow-but-streaming. Free tier: no credit card, 30
 *   req/min, up to 14,400 req/day — plenty for this app's current traffic.
 * - NVIDIA NIM / kimi-k3 (fallback, when only NVIDIA_API_KEY is set): kept
 *   working exactly as before so nothing breaks if Groq isn't configured
 *   yet. Genuinely a reasoning model — real 20-30s "thinking" time before
 *   the first user-facing token, independent of prompt size (confirmed by
 *   testing: trimming the venue digest from 200+ to 60 venues didn't
 *   meaningfully change it). Re-verify against GET
 *   https://integrate.api.nvidia.com/v1/models if kimi-k3 ever 410s.
 *
 * SECURITY (Pre-Launch Audit, Phase 1 #6): rate-limited by IP rather than
 * gated behind auth — the Concierge is a guest-accessible feature today
 * (no login wall anywhere else in its flow), so requiring auth here would
 * be a product change, not a security fix.
 */
const GROQ_CHAT_URL = "https://api.groq.com/openai/v1/chat/completions";
const GROQ_MODEL = "llama-3.3-70b-versatile";
const NVIDIA_CHAT_URL = "https://integrate.api.nvidia.com/v1/chat/completions";
const NVIDIA_MODEL = "moonshotai/kimi-k3";

function resolveProvider(): { apiKey: string; chatUrl: string; model: string } | null {
  if (process.env.GROQ_API_KEY) {
    return { apiKey: process.env.GROQ_API_KEY, chatUrl: GROQ_CHAT_URL, model: GROQ_MODEL };
  }
  if (process.env.NVIDIA_API_KEY) {
    return { apiKey: process.env.NVIDIA_API_KEY, chatUrl: NVIDIA_CHAT_URL, model: NVIDIA_MODEL };
  }
  return null;
}

export async function POST(request: Request) {
  const ip = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "unknown";
  // 20 requests/minuto por IP — un chat manda muchos más turnos que el
  // viejo formulario de un solo tiro, así que el límite anterior de 10/min
  // se quedaba corto para una conversación real de varios mensajes.
  const withinLimit = await checkRateLimit(`concierge:${ip}`, {
    maxRequests: 20,
    windowSeconds: 60,
  });
  if (!withinLimit) {
    return Response.json({ error: "rate_limited" }, { status: 429 });
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return Response.json({ error: "invalid_json" }, { status: 400 });
  }
  const parsed = conciergeChatRequestSchema.safeParse(body);
  if (!parsed.success) {
    return Response.json({ error: "invalid_request" }, { status: 400 });
  }

  const provider = resolveProvider();
  if (!provider) {
    return Response.json({ error: "ai_not_configured" }, { status: 503 });
  }

  const allVenues = await getVenues();
  const targetCity = parsed.data.city ?? "Miami";
  const cityVenues = allVenues.filter((v) => v.city === targetCity);
  const venues = cityVenues.length > 0 ? cityVenues : allVenues;
  const conversationText = parsed.data.messages.map((m) => m.content).join(" ");
  const systemInstruction = buildConciergeSystemPrompt(selectRelevantVenues(venues, conversationText));

  let upstream: Response;
  try {
    upstream = await fetch(provider.chatUrl, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${provider.apiKey}`,
        "Content-Type": "application/json",
        Accept: "text/event-stream",
      },
      body: JSON.stringify({
        model: provider.model,
        messages: [
          { role: "system", content: systemInstruction },
          ...parsed.data.messages,
        ],
        temperature: 0.8,
        max_tokens: 2048,
        stream: true,
      }),
    });
  } catch (e) {
    console.error("Concierge upstream fetch failed:", e);
    return Response.json({ error: "ai_unavailable" }, { status: 502 });
  }

  if (!upstream.ok || !upstream.body) {
    console.error(`Concierge upstream call failed: HTTP ${upstream.status}`, await upstream.text().catch(() => ""));
    return Response.json({ error: "ai_unavailable" }, { status: 502 });
  }

  // NVIDIA streams OpenAI-style SSE ("data: {json}\n\n", ending in
  // "data: [DONE]"). The client just wants plain text — this transform
  // unwraps it, plus two 1-byte control markers (\x01, \x02) that never
  // occur in real text: \x01 fires the instant the model shows ANY sign of
  // life (its internal "reasoning_content" — kimi-k3 is a reasoning model
  // and can think for 20-30s before its real answer starts), so the client
  // can flip from "idle" to a visible "thinking" state within ~1s instead
  // of showing nothing while the model works. \x02 fires when the real,
  // user-facing "content" starts — everything after it is the actual
  // message, forwarded as before.
  const decoder = new TextDecoder();
  let buffer = "";
  let thinkingSignaled = false;
  let contentSignaled = false;
  const textStream = new ReadableStream<Uint8Array>({
    async start(controller) {
      const reader = upstream.body!.getReader();
      const encoder = new TextEncoder();
      try {
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          buffer += decoder.decode(value, { stream: true });
          const lines = buffer.split("\n");
          buffer = lines.pop() ?? "";
          for (const line of lines) {
            const trimmed = line.trim();
            if (!trimmed.startsWith("data:")) continue;
            const payload = trimmed.slice(5).trim();
            if (payload === "[DONE]") continue;
            try {
              const chunk = JSON.parse(payload);
              const delta = chunk.choices?.[0]?.delta;
              if (!contentSignaled && typeof delta?.reasoning_content === "string" && !thinkingSignaled) {
                thinkingSignaled = true;
                controller.enqueue(encoder.encode("\x01"));
              }
              if (typeof delta?.content === "string" && delta.content.length > 0) {
                if (!contentSignaled) {
                  contentSignaled = true;
                  controller.enqueue(encoder.encode("\x02"));
                }
                controller.enqueue(encoder.encode(delta.content));
              }
            } catch {
              // Partial/malformed SSE line — skip it, next chunk carries on.
            }
          }
        }
      } catch (e) {
        console.error("Concierge stream read failed:", e);
      } finally {
        controller.close();
      }
    },
  });

  return new Response(textStream, {
    headers: {
      "Content-Type": "text/plain; charset=utf-8",
      "Cache-Control": "no-cache, no-transform",
      "X-Accel-Buffering": "no",
    },
  });
}
