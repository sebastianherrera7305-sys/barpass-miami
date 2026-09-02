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
  // Bug fix (2026-09-02): la app ya mandaba budget/groupSize/neighborhood
  // en el body, pero este schema no los declaraba — Zod los descartaba en
  // silencio (modo "strip" por default) y nunca llegaban al prompt. Los
  // quick actions "Cheaper"/"More upscale" no tenían ningún efecto real en
  // el camino de IA por esto.
  budget: z.number().nonnegative().max(10000).optional(),
  groupSize: z.number().int().positive().max(50).optional(),
  neighborhood: z.string().max(100).optional(),
  // Fase 4 real: Free vs Premium generan planes distintos (menos/más
  // paradas, memoria de preferencias), no solo distinto límite de uso.
  tier: z.enum(["free", "premium"]).optional(),
  // Memoria liviana entre conversaciones, solo Premium — ver
  // PlanPreferencesService del lado iOS. Frase corta, no PII.
  rememberedVibe: z.string().max(200).optional(),
});

export type ValidatedNightPlan = z.infer<typeof nightPlanSchema>;
