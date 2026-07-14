import { z } from "zod";

/**
 * Zod validation for concierge output.
 * The LLM's JSON is untrusted input — this schema is the boundary between
 * the model and the UI. Anything that fails validation never renders.
 */
export const planStopSchema = z.object({
  time: z.string().min(1),
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

export const conciergeRequestSchema = z.object({
  prompt: z.string().min(2).max(600),
  // Slugs ya recomendados en esta sesión — sin esto, Remy le manda el mismo
  // catálogo completo en el mismo orden cada vez y termina repitiendo las
  // mismas venues turno tras turno.
  excludeSlugs: z.array(z.string()).max(30).optional(),
});

export type ValidatedNightPlan = z.infer<typeof nightPlanSchema>;
