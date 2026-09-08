import { getVenuesByCity } from "@/features/venues/services/venue-service";
import { buildConciergeSystemPrompt, selectRelevantVenues } from "@/features/ai/services/concierge-prompt";
import { conciergeChatRequestSchema } from "@/features/ai/services/plan-schema";
import { detectUserLanguage, groundPlanBlock } from "@/features/ai/services/plan-grounding";
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
/** Primary NVIDIA model. Measured 2026-09-06 against this account, 60-venue
 * prompt, 350-token reply: gpt-oss-20b at reasoning_effort "low" → 0.7s to
 * first token, 5.3s total. kimi-k3 on the same prompt → 4.4s to first token,
 * 29s total (and 85s in production with the real prompt), because it thinks
 * at length before answering and that can't be turned off on NIM (the
 * `thinking:false` template kwarg is ignored). In production Vercel has ONLY
 * NVIDIA_API_KEY — no Groq key was ever set there — so this model IS the
 * chat for every real user; it has to be the fast one. Every other fast
 * instruct model on NIM (llama-3.1/3.3-70b, llama-4, nemotron, mistral)
 * returned 410/404 for this account — only kimi-k3 and gpt-oss-20b remain. */
const NVIDIA_FAST_MODEL = "openai/gpt-oss-20b";
const NVIDIA_FALLBACK_MODEL = "moonshotai/kimi-k3";

interface Provider {
  name: string;
  apiKey: string;
  chatUrl: string;
  model: string;
  timeoutMs: number;
  /** Extra OpenAI-compatible body fields this model needs (e.g. reasoning_effort). */
  extraBody?: Record<string, unknown>;
}

/** Every configured provider, in preference order — Groq first (fast),
 * NVIDIA second (slower reasoning model, but a real fallback). Previously
 * this picked ONE provider and had no runtime fallback: 2026-09-05, a
 * misconfigured Groq key (a copy-paste mistake, same class of bug as the
 * earlier NVIDIA_API_KEY= incident) took the ENTIRE Concierge down even
 * though NVIDIA_API_KEY was still valid — a single bad key shouldn't be
 * able to do that when a second real option exists.
 *
 * `timeoutMs` bounds how long we wait for that provider to even START
 * responding before moving on — 2026-09-05, a real user hit a ~60s reply
 * with Groq configured and working (confirmed separately, same day, at a
 * normal ~3-8s). The old retry loop only caught a provider that failed
 * outright (non-ok status, thrown fetch); it did nothing for one that's
 * just slow to connect, which is exactly what an intermittent upstream
 * slowdown looks like. Groq's own normal ceiling is a few seconds, so 10s
 * is generous; NVIDIA is a genuine 20-30s reasoning model, so it gets far
 * more room before we give up on it too.
 */
function resolveProviders(): Provider[] {
  const providers: Provider[] = [];
  if (process.env.GROQ_API_KEY) {
    providers.push({ name: "groq", apiKey: process.env.GROQ_API_KEY, chatUrl: GROQ_CHAT_URL, model: GROQ_MODEL, timeoutMs: 10_000 });
  }
  if (process.env.NVIDIA_API_KEY) {
    providers.push({
      name: "nvidia-fast", apiKey: process.env.NVIDIA_API_KEY, chatUrl: NVIDIA_CHAT_URL,
      model: NVIDIA_FAST_MODEL, timeoutMs: 15_000, extraBody: { reasoning_effort: "low" },
    });
    // Same key, slow model — only reached if gpt-oss-20b is down or rate-limited.
    providers.push({ name: "nvidia-kimi", apiKey: process.env.NVIDIA_API_KEY, chatUrl: NVIDIA_CHAT_URL, model: NVIDIA_FALLBACK_MODEL, timeoutMs: 45_000 });
  }
  return providers;
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

  const providers = resolveProviders();
  if (providers.length === 0) {
    return Response.json({ error: "ai_not_configured" }, { status: 503 });
  }

  const targetCity = parsed.data.city ?? "Miami";
  let venues = await getVenuesByCity(targetCity);
  // Unknown/mistyped city (empty result) — fall back to Miami rather than
  // the full 23-city catalog, keeping the same fast, scoped fetch.
  if (venues.length === 0 && targetCity !== "Miami") {
    venues = await getVenuesByCity("Miami");
  }
  const conversationText = parsed.data.messages.map((m) => m.content).join(" ");

  // Real user context (2026-09-06): where they are, what they like, what
  // time it is THERE. Without it the digest was the same for "what's next"
  // from inside a venue at 2 AM and for Friday planning from the couch.
  const ctx = parsed.data.context;
  const currentVenue = ctx?.currentVenueId ? venues.find((v) => v.id === ctx.currentVenueId) : undefined;
  const favorites = ctx?.favoriteVenueIds?.length
    ? venues.filter((v) => ctx.favoriteVenueIds!.includes(v.id))
    : [];
  const origin = ctx?.userLocation ?? (currentVenue ? { lat: currentVenue.lat, lng: currentVenue.lng } : undefined);
  const timeZone = venues[0]?.timezone ?? "America/New_York";
  const localParts = new Intl.DateTimeFormat("en-US", { timeZone, hour: "numeric", minute: "numeric", hour12: false })
    .formatToParts(new Date());
  const hourPart = Number(localParts.find((p) => p.type === "hour")?.value ?? NaN);
  const minutePart = Number(localParts.find((p) => p.type === "minute")?.value ?? NaN);
  const nowMin = Number.isFinite(hourPart) && Number.isFinite(minutePart) ? (hourPart % 24) * 60 + minutePart : undefined;

  const shortlist = selectRelevantVenues(venues, conversationText, 35, {
    origin,
    nowMin,
    favoriteIds: new Set(ctx?.favoriteVenueIds ?? []),
    excludeId: currentVenue?.id,
  });
  const systemInstruction = buildConciergeSystemPrompt(shortlist, { currentVenue, favorites, origin, timeZone });
  // The last message decides; if it's too short to tell (a venue name, "ok"),
  // fall back to the whole conversation rather than defaulting to English.
  const lastUserMessage = [...parsed.data.messages].reverse().find((m) => m.role === "user")?.content ?? "";
  const replyLanguage = detectUserLanguage(lastUserMessage)
    ?? detectUserLanguage(parsed.data.messages.filter((m) => m.role === "user").map((m) => m.content).join(" "));

  let upstream: Response | null = null;
  let servedBy: Provider | null = null;
  for (const provider of providers) {
    const timeoutController = new AbortController();
    const timeoutId = setTimeout(() => timeoutController.abort(), provider.timeoutMs);
    try {
      const attempt = await fetch(provider.chatUrl, {
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
            // Recency-weighted, unambiguous. The LANGUAGE RULE at the top of
            // a ~4K-token system prompt was being ignored by the 20B model
            // on 2 of 6 eval prompts (Spanish in, English out). A one-line
            // instruction placed AFTER the user's message is what it obeys.
            ...(replyLanguage
              ? [{
                  role: "system",
                  content: replyLanguage === "es"
                    ? "Responde SOLO en español neutro latinoamericano (nada de 'vos'/'che'). Ni una frase en inglés."
                    : "Reply ONLY in natural American English. Not one sentence in another language.",
                }]
              : []),
          ],
          temperature: 0.8,
          // A 3-stop plan block + 2 sentences is ~500 tokens; 2048 only ever
          // let a rambling reply run long (and slow).
          max_tokens: 1000,
          stream: true,
          ...provider.extraBody,
        }),
        signal: timeoutController.signal,
      });
      if (attempt.ok && attempt.body) {
        upstream = attempt;
        servedBy = provider;
        break;
      }
      console.error(`Concierge ${provider.name} call failed: HTTP ${attempt.status}`, await attempt.text().catch(() => ""));
    } catch (e) {
      const isTimeout = e instanceof Error && e.name === "AbortError";
      console.error(`Concierge ${provider.name} fetch ${isTimeout ? `timed out after ${provider.timeoutMs}ms` : "failed"}:`, isTimeout ? "" : e);
    } finally {
      clearTimeout(timeoutId);
    }
  }

  if (!upstream || !upstream.body) {
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
  // Plan-block grounding (2026-09-06): the ```json fence is held back until
  // it closes, re-anchored to the shortlist (groundPlanBlock), then emitted
  // whole. Costs nothing visible — the clients already hide an open fence
  // and only render the card once it closes — and guarantees every stop's
  // venueId is a real catalog UUID the model was shown.
  let fenceBuffer: string | null = null;
  let pending = ""; // text we've seen but not yet emitted (may hold a partial "```json")
  const FENCE_OPEN = "```json";
  const textStream = new ReadableStream<Uint8Array>({
    async start(controller) {
      const reader = upstream.body!.getReader();
      const encoder = new TextEncoder();
      const emit = (s: string) => { if (s.length > 0) controller.enqueue(encoder.encode(s)); };
      // The 20B model keeps bolding venue names despite the plain-text rule;
      // the iOS bubble renders raw text, so "**Amor Miami**" showed literally.
      // Prose (never the JSON block) has its bold markers removed here.
      const emitProse = (s: string) => emit(s.replace(/\*\*/g, ""));
      const onContent = (piece: string) => {
        if (fenceBuffer !== null) {
          fenceBuffer += piece;
          const close = fenceBuffer.indexOf("```", FENCE_OPEN.length);
          if (close === -1) return;
          const inner = fenceBuffer.slice(FENCE_OPEN.length, close);
          const after = fenceBuffer.slice(close + 3);
          const grounded = groundPlanBlock(inner.trim(), shortlist);
          // null = every stop was invented; drop the block entirely rather
          // than render an itinerary of places that don't exist.
          if (grounded) emit(`${FENCE_OPEN}\n${grounded}\n\`\`\``);
          fenceBuffer = null;
          pending = "";
          onContent(after);
          return;
        }
        pending += piece;
        const open = pending.indexOf(FENCE_OPEN);
        if (open !== -1) {
          emitProse(pending.slice(0, open));
          fenceBuffer = pending.slice(open);
          pending = "";
          // The fence may have opened AND closed inside this same piece.
          const rest = fenceBuffer;
          fenceBuffer = FENCE_OPEN;
          onContent(rest.slice(FENCE_OPEN.length));
          return;
        }
        // Hold back only a possible partial "```json" prefix (or a lone "*"
        // that might be the first half of "**") at the tail.
        let hold = 0;
        for (let n = Math.min(FENCE_OPEN.length - 1, pending.length); n > 0; n--) {
          if (FENCE_OPEN.startsWith(pending.slice(pending.length - n))) { hold = n; break; }
        }
        if (hold === 0 && pending.endsWith("*")) hold = 1;
        emitProse(pending.slice(0, pending.length - hold));
        pending = pending.slice(pending.length - hold);
      };
      const flush = () => {
        // Stream ended: anything still held (a fence that never closed, a
        // partial prefix) goes out as-is rather than being lost.
        if (fenceBuffer !== null) { emit(fenceBuffer); fenceBuffer = null; }
        emitProse(pending);
        pending = "";
      };
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
                onContent(delta.content);
              }
            } catch {
              // Partial/malformed SSE line — skip it, next chunk carries on.
            }
          }
        }
      } catch (e) {
        console.error("Concierge stream read failed:", e);
      } finally {
        flush();
        controller.close();
      }
    },
  });

  return new Response(textStream, {
    headers: {
      "Content-Type": "text/plain; charset=utf-8",
      "Cache-Control": "no-cache, no-transform",
      // Which provider/model actually answered — so "the chat is slow" can
      // be measured with one curl instead of guessed at.
      "X-BP-Provider": servedBy?.name ?? "unknown",
      "X-BP-Model": servedBy?.model ?? "unknown",
      "X-Accel-Buffering": "no",
    },
  });
}
