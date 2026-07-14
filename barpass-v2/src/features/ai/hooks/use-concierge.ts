"use client";

import { useMutation } from "@tanstack/react-query";
import type { NightPlan } from "@/types";

/**
 * Client hook for the AI Concierge.
 * Wraps POST /api/concierge in a TanStack mutation — components get
 * loading/error/data states for free.
 */
interface ConciergeRequest {
  prompt: string;
  /** Slugs ya recomendados antes en esta sesión — evita que Remy repita venues. */
  excludeSlugs?: string[];
}

export function useConcierge() {
  return useMutation<NightPlan, Error, ConciergeRequest>({
    mutationFn: async ({ prompt, excludeSlugs }: ConciergeRequest) => {
      const res = await fetch("/api/concierge", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ prompt, excludeSlugs }),
      });
      if (!res.ok) {
        const body = (await res.json().catch(() => null)) as
          | { error?: string }
          | null;
        throw new Error(body?.error ?? "concierge_failed");
      }
      return res.json() as Promise<NightPlan>;
    },
  });
}
