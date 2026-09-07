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
