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
  content: z.string().min(1).max(4000),
});

export const conciergeChatRequestSchema = z.object({
  // Full turn history — this (not excludeSlugs) is what keeps Remy from
  // repeating a venue it already suggested earlier in the same chat, since
  // the model can literally see its own prior messages.
  messages: z.array(conciergeChatMessageSchema).min(1).max(40),
  // Scopes the venue digest to one metro. Without this, every call embedded
  // the ENTIRE catalog (1800+ venues across 23 cities once the iOS app's
  // multi-city expansion landed here too) into one prompt — expensive,
  // slow, and Remy could just as easily suggest a Miami stop to someone in
  // Austin. Optional so the web Concierge (still Miami-only in its own UI)
  // keeps working with no caller change; falls back to Miami server-side.
  city: z.string().min(1).max(60).optional(),
});

export type ConciergeChatMessage = z.infer<typeof conciergeChatMessageSchema>;
export type ValidatedNightPlan = z.infer<typeof nightPlanSchema>;
