import { getVenuesByCity } from "@/features/venues/services/venue-service";
import { buildConciergeSystemPrompt, selectRelevantVenues } from "@/features/ai/services/concierge-prompt";
import { conciergeChatRequestSchema, trimConciergeHistory } from "@/features/ai/services/plan-schema";
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

/**
 * Vercel function budget for one chat turn. Production has already served
 * 85s kimi-k3 replies (2026-09-06), so the account's ceiling is above the
 * 60s legacy default; this pins the budget explicitly and stays under the
 * iOS client's own 150s request timeout. The in-route watchdog below
 * (STREAM_TOTAL_MS / STREAM_IDLE_MS) ends the stream cleanly BEFORE this
 * limit is reached — a platform kill mid-stream is a bare cut the client
 * can't distinguish from a finished reply.
 */
export const maxDuration = 120;
/** Hard ceiling on one upstream stream, connect included. */
const STREAM_TOTAL_MS = 110_000;
/** Abort if the upstream sends NOTHING for this long. Both NIM models stream
 * reasoning deltas continuously while thinking, so a healthy stream is never
 * quiet for 45s — only a hung connection is. */
const STREAM_IDLE_MS = 45_000;
const WATCHDOG_TICK_MS = 2_000;

/** Which upstream statuses mean "try the next provider". 429/5xx are the
 * provider being busy or down; 401/403/404/410 are THAT provider's key or
 * model being wrong (2026-09-05: a bad Groq key must not take the whole chat
 * down while NVIDIA is fine; every retired NIM model 410s). 400/413/422 mean
 * OUR request is malformed and would be rejected by the next provider just
 * the same — surface it instead of burning a second call. */
function isRetryableUpstreamStatus(status: number): boolean {
  if (status >= 500) return true;
  return [401, 403, 404, 408, 409, 410, 425, 429].includes(status);
}

/** Error shape every client renders: `error` is the stable machine code the
 * iOS `friendlyServerMessage` switch keys on (unknown codes fall back to the
 * "Remy isn't available" copy), `message` is a human default for anything
 * else, `retryable` tells a client whether "try again" is honest. */
function aiError(
  code: string,
  status: number,
  message: string,
  { retryable = false, retryAfterSeconds }: { retryable?: boolean; retryAfterSeconds?: number } = {},
): Response {
  const headers: Record<string, string> = { "Cache-Control": "no-store" };
  if (retryAfterSeconds) headers["Retry-After"] = String(retryAfterSeconds);
  return Response.json({ error: code, message, retryable }, { status, headers });
}

/** An invalid IANA name from the catalog must not 500 the chat: both
 * Intl.DateTimeFormat and toLocaleString throw RangeError on one. */
function safeTimeZone(tz: string | undefined, fallback = "America/New_York"): string {
  if (!tz) return fallback;
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: tz });
    return tz;
  } catch {
    console.error(`Concierge: invalid venue timezone "${tz}", using ${fallback}`);
    return fallback;
  }
}

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
  // Plus a daily cap (2026-09-12): this route is deliberately open (the
  // iOS app sends no bearer here — guest-accessible by design, see
  // APIClient.streamConciergeChat), so the per-minute window alone lets one
  // IP run ~28K model calls a day. 400/day is far above any real user's
  // chatting and bounds what an abuser can cost. Both checks fail-open.
  const [withinMinute, withinDay] = await Promise.all([
    checkRateLimit(`concierge:${ip}`, { maxRequests: 20, windowSeconds: 60 }),
    checkRateLimit(`concierge-day:${ip}`, { maxRequests: 400, windowSeconds: 86_400 }),
  ]);
  if (!withinMinute) {
    return aiError("rate_limited", 429, "Remy is busy — give it a minute and try again.", { retryable: true, retryAfterSeconds: 60 });
  }
  if (!withinDay) {
    return aiError("rate_limited", 429, "You've reached today's chat limit. Remy will be back tomorrow.", { retryAfterSeconds: 3600 });
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return aiError("invalid_json", 400, "Malformed request body.");
  }
  const parsed = conciergeChatRequestSchema.safeParse(body);
  if (!parsed.success) {
    return aiError("invalid_request", 400, "Malformed chat request.");
  }

  const providers = resolveProviders();
  if (providers.length === 0) {
    return aiError("ai_not_configured", 503, "Remy isn't available right now.");
  }

  // The user already left the screen (the iOS stream cancels its URLSession
  // task on dismiss) — don't spend a model call answering nobody.
  if (request.signal.aborted) {
    return aiError("client_closed", 499, "Client went away.");
  }

  const targetCity = parsed.data.city ?? "Miami";
  let venues: Awaited<ReturnType<typeof getVenuesByCity>> = [];
  try {
    venues = await getVenuesByCity(targetCity);
    // Unknown/mistyped city (empty result) — fall back to Miami rather than
    // the full 23-city catalog, keeping the same fast, scoped fetch.
    if (venues.length === 0 && targetCity !== "Miami") {
      venues = await getVenuesByCity("Miami");
    }
  } catch (e) {
    // getVenuesByCity already falls back to the full-catalog fetch; if THAT
    // throws too, Supabase is down. A 503 the client renders beats a 500.
    console.error("Concierge venue fetch failed:", e);
  }
  if (venues.length === 0) {
    // With no catalog the model has nothing real to ground on and would
    // invent venues; every plan block would be dropped by grounding anyway.
    return aiError("venues_unavailable", 503, "Remy can't reach the venue list right now — try again in a moment.", { retryable: true, retryAfterSeconds: 15 });
  }
  // Bound what reaches the model: newest turns within a token budget.
  const history = trimConciergeHistory(parsed.data.messages);
  const conversationText = history.map((m) => m.content).join(" ");

  // Real user context (2026-09-06): where they are, what they like, what
  // time it is THERE. Without it the digest was the same for "what's next"
  // from inside a venue at 2 AM and for Friday planning from the couch.
  const ctx = parsed.data.context;
  const currentVenue = ctx?.currentVenueId ? venues.find((v) => v.id === ctx.currentVenueId) : undefined;
  const favorites = ctx?.favoriteVenueIds?.length
    ? venues.filter((v) => ctx.favoriteVenueIds!.includes(v.id))
    : [];
  const origin = ctx?.userLocation ?? (currentVenue ? { lat: currentVenue.lat, lng: currentVenue.lng } : undefined);
  const timeZone = safeTimeZone(venues[0]?.timezone);
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
  const lastUserMessage = [...history].reverse().find((m) => m.role === "user")?.content ?? "";
  const replyLanguage = detectUserLanguage(lastUserMessage)
    ?? detectUserLanguage(history.filter((m) => m.role === "user").map((m) => m.content).join(" "));

  let upstream: Response | null = null;
  let servedBy: Provider | null = null;
  // One controller outlives the connect phase: it aborts the upstream
  // stream on client disconnect, on the idle/total watchdog, and when the
  // response stream is cancelled. A new one per provider attempt.
  let upstreamController = new AbortController();
  let terminal: { status: number; provider: string } | null = null;
  let sawRateLimit = false;
  for (const provider of providers) {
    if (request.signal.aborted) break;
    upstreamController = new AbortController();
    const connectTimer = setTimeout(() => upstreamController.abort(new Error("connect_timeout")), provider.timeoutMs);
    const onClientAbort = () => upstreamController.abort(new Error("client_disconnected"));
    request.signal.addEventListener("abort", onClientAbort, { once: true });
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
            ...history,
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
        signal: upstreamController.signal,
      });
      if (attempt.ok && attempt.body) {
        upstream = attempt;
        servedBy = provider;
        // Keep the client-abort listener: it now guards the streaming phase.
        clearTimeout(connectTimer);
        break;
      }
      const detail = await attempt.text().catch(() => "");
      console.error(`Concierge ${provider.name} call failed: HTTP ${attempt.status}`, detail.slice(0, 500));
      if (attempt.status === 429) sawRateLimit = true;
      if (!isRetryableUpstreamStatus(attempt.status)) {
        terminal = { status: attempt.status, provider: provider.name };
        break;
      }
    } catch (e) {
      if (request.signal.aborted) break;
      const reason = upstreamController.signal.reason;
      const isTimeout = reason instanceof Error && reason.message === "connect_timeout";
      console.error(`Concierge ${provider.name} fetch ${isTimeout ? `timed out after ${provider.timeoutMs}ms` : "failed"}:`, isTimeout ? "" : e);
    } finally {
      clearTimeout(connectTimer);
      if (!upstream) request.signal.removeEventListener("abort", onClientAbort);
    }
  }

  if (request.signal.aborted) {
    upstreamController.abort(new Error("client_disconnected"));
    return aiError("client_closed", 499, "Client went away.");
  }
  if (terminal) {
    // Our request was rejected as malformed (400/413/422) — a bug on our
    // side, not a busy provider; say so instead of inviting a retry.
    return aiError("ai_request_rejected", 502, "Remy couldn't process that message. Try rephrasing it.");
  }
  if (!upstream || !upstream.body) {
    return aiError(
      "ai_unavailable",
      sawRateLimit ? 503 : 502,
      "Remy is busy right now — try again in a moment.",
      { retryable: true, retryAfterSeconds: sawRateLimit ? 20 : 10 },
    );
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
  const upstreamAbort = upstreamController;
  const startedAt = Date.now();
  let lastChunkAt = startedAt;
  let watchdog: ReturnType<typeof setInterval> | null = null;
  const textStream = new ReadableStream<Uint8Array>({
    async start(controller) {
      const reader = upstream.body!.getReader();
      const encoder = new TextEncoder();
      // Hung or stalled upstream: a stream that goes quiet, or one that
      // just never ends, used to sit until Vercel killed the function —
      // a bare cut the client can't tell from a finished reply. Aborting
      // the reader ends it through the normal flush/close path instead.
      watchdog = setInterval(() => {
        const now = Date.now();
        if (now - lastChunkAt > STREAM_IDLE_MS) {
          console.error(`Concierge ${servedBy?.name} stream idle for ${STREAM_IDLE_MS}ms — aborting`);
          upstreamAbort.abort(new Error("stream_idle"));
        } else if (now - startedAt > STREAM_TOTAL_MS) {
          console.error(`Concierge ${servedBy?.name} stream exceeded ${STREAM_TOTAL_MS}ms — aborting`);
          upstreamAbort.abort(new Error("stream_total"));
        }
      }, WATCHDOG_TICK_MS);
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
        // Hold back only a possible partial "```json" prefix, or a trailing
        // "*"/"**" that might be the start of a bold marker, at the tail.
        // Both stars must be held (2026-09-12): when a token was exactly
        // "**", holding one emitted the other alone, so "**Sugar**" streamed
        // as "*Sugar*" — a stray star the iOS bubble shows literally.
        let hold = 0;
        for (let n = Math.min(FENCE_OPEN.length - 1, pending.length); n > 0; n--) {
          if (FENCE_OPEN.startsWith(pending.slice(pending.length - n))) { hold = n; break; }
        }
        if (hold === 0) hold = pending.endsWith("**") ? 2 : pending.endsWith("*") ? 1 : 0;
        emitProse(pending.slice(0, pending.length - hold));
        pending = pending.slice(pending.length - hold);
      };
      const flush = () => {
        // Stream ended with a ```json fence still open (token limit hit,
        // upstream cut, watchdog abort): the clients only render a CLOSED
        // fence — iOS `extractChatReplyParts` returns the raw text when it
        // can't find the closing ``` — so emitting it as-is showed half a
        // JSON object in the chat bubble. A partial plan can't be grounded
        // or rendered; drop it. If nothing else was said, the client sees an
        // empty reply and shows its "try again" state, which is honest.
        if (fenceBuffer !== null) {
          console.error(`Concierge ${servedBy?.name}: stream ended inside an open plan fence (${fenceBuffer.length} chars) — dropped`);
          fenceBuffer = null;
        }
        emitProse(pending);
        pending = "";
      };
      try {
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          lastChunkAt = Date.now();
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
              // Some OpenAI-compatible servers report a mid-stream failure
              // as a 200 SSE event carrying an error object. Log it; the
              // stream then ends through the normal flush/close.
              if (chunk && typeof chunk === "object" && "error" in chunk && !("choices" in chunk)) {
                console.error(`Concierge ${servedBy?.name} in-stream error:`, JSON.stringify(chunk.error).slice(0, 300));
                continue;
              }
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
        const reason = upstreamAbort.signal.reason;
        const why = reason instanceof Error ? reason.message : null;
        if (why === "client_disconnected") {
          // Not an error: the user left. Nothing to flush to nobody.
        } else {
          console.error(`Concierge stream read failed (${why ?? "upstream"}):`, why ? "" : e);
        }
      } finally {
        if (watchdog) clearInterval(watchdog);
        flush();
        try { controller.close(); } catch { /* already closed by cancel() */ }
      }
    },
    cancel() {
      // The response consumer went away (client disconnect surfaced through
      // the stream): stop the upstream generation so it doesn't run to
      // completion for nobody.
      if (watchdog) clearInterval(watchdog);
      upstreamAbort.abort(new Error("client_disconnected"));
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
