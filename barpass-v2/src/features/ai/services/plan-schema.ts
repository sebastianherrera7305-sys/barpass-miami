import { z } from "zod";

/**
 * Zod validation for concierge output.
 * The LLM's JSON is untrusted input — this schema is the boundary between
 * the model and the UI. Anything that fails validation never renders.
 */
export const planStopSchema = z.object({
  time: z.string().min(1),
  // Optional — a model that ignores the id-from-catalog instruction and
  // only echoes the slug shouldn't fail the whole plan over it. Clients
  // that need real navigation (the iOS app) fall back to resolving by
  // venueSlug/venueName against their own already-loaded catalog when
  // venueId is missing.
  venueId: z.string().min(1).optional(),
  venueSlug: z.string().min(1),
  venueName: z.string().min(1),
  note: z.string().min(1),
  estimatedSpend: z.number().nonnegative(),
});

export const nightPlanSchema = z.object({
  title: z.string().min(1),
  summary: z.string().min(1),
  stops: z.array(planStopSchema).min(1).max(6),
  totalEstimate: z.number().nonnegative(),
  insiderTip: z.string().min(1),
});

// Legacy single-shot request — kept only so nothing on disk references a
// type that no longer exists; the live route is chat-only now (see below).
export const conciergeRequestSchema = z.object({
  prompt: z.string().min(2).max(600),
  excludeSlugs: z.array(z.string()).max(30).optional(),
  city: z.string().min(1).max(60).optional(),
});

export const conciergeChatMessageSchema = z.object({
  role: z.enum(["user", "assistant"]),
  // 8000, not 4000 (2026-09-12): the iOS app echoes Remy's own prior replies
  // back as `assistant` turns, and a reply with a full plan block runs
  // ~1500-3000 chars. The per-request token budget is enforced by
  // trimConciergeHistory below, not by rejecting a long turn with a 400
  // the user can't do anything about.
  content: z.string().min(1).max(8000),
});

export const conciergeChatRequestSchema = z.object({
  // Full turn history — this (not excludeSlugs) is what keeps Remy from
  // repeating a venue it already suggested earlier in the same chat, since
  // the model can literally see its own prior messages.
  // 200, not 40 (2026-09-12): the iOS app sends the WHOLE persisted chat
  // on every turn with no client-side cap, so a chat that reached 41
  // messages was rejected with 400 invalid_request on every turn from then
  // on — permanently, for that chat. Accept a long history and trim it
  // server-side (trimConciergeHistory) instead of failing the request.
  messages: z.array(conciergeChatMessageSchema).min(1).max(200),
  // Scopes the venue digest to one metro. Without this, every call embedded
  // the ENTIRE catalog (1800+ venues across 23 cities once the iOS app's
  // multi-city expansion landed here too) into one prompt — expensive,
  // slow, and Remy could just as easily suggest a Miami stop to someone in
  // Austin. Optional so the web Concierge (still Miami-only in its own UI)
  // keeps working with no caller change; falls back to Miami server-side.
  city: z.string().min(1).max(60).optional(),
  // Where the user actually is and what they already like — the difference
  // between "here are clubs in Miami" and "you're at Factory Town, here's
  // what's 8 minutes away and still open at 3 AM". All optional; the web
  // Concierge sends none of it and keeps working.
  context: z
    .object({
      /** venues.id the user is checked in at right now. */
      currentVenueId: z.string().min(1).max(64).optional(),
      /** venues.id list the user has favorited — a taste signal, not a shortlist. */
      favoriteVenueIds: z.array(z.string().min(1).max(64)).max(30).optional(),
      /** Device location, when the app already has it (no new prompt is triggered for this). */
      userLocation: z.object({ lat: z.number().min(-90).max(90), lng: z.number().min(-180).max(180) }).optional(),
    })
    .optional(),
});

export type ConciergeContextInput = z.infer<typeof conciergeChatRequestSchema>["context"];

export type ConciergeChatMessage = z.infer<typeof conciergeChatMessageSchema>;
export type ValidatedNightPlan = z.infer<typeof nightPlanSchema>;

/** Most recent turns to send upstream. 24 turns is ~12 exchanges — more than
 * a night-planning chat needs for continuity; older turns only add prompt
 * tokens (cost + latency) on every request. */
export const CONCIERGE_MAX_HISTORY_TURNS = 24;
/** Character budget for the history that goes upstream (~6K tokens). */
export const CONCIERGE_MAX_HISTORY_CHARS = 24_000;

/**
 * Bounds what reaches the model: the newest turns, most-recent first, until
 * either the turn cap or the character budget is hit. The last message is
 * always kept (it's the one being answered), truncated to the budget if it
 * alone exceeds it. Pure — nothing here throws.
 */
export function trimConciergeHistory(
  messages: ConciergeChatMessage[],
  { maxTurns = CONCIERGE_MAX_HISTORY_TURNS, maxChars = CONCIERGE_MAX_HISTORY_CHARS } = {},
): ConciergeChatMessage[] {
  if (messages.length === 0) return [];
  const last = messages[messages.length - 1];
  const kept: ConciergeChatMessage[] = [
    last.content.length > maxChars ? { ...last, content: last.content.slice(0, maxChars) } : last,
  ];
  let chars = kept[0].content.length;
  for (let i = messages.length - 2; i >= 0 && kept.length < maxTurns; i--) {
    const m = messages[i];
    if (chars + m.content.length > maxChars) break;
    chars += m.content.length;
    kept.push(m);
  }
  return kept.reverse();
}
