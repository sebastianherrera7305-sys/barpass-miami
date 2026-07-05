"use client";

import { useMutation } from "@tanstack/react-query";
import type { NightPlan } from "@/types";

/**
 * Client hook for the AI Concierge.
 * Wraps POST /api/concierge in a TanStack mutation — components get
 * loading/error/data states for free.
 */
export function useConcierge() {
  return useMutation<NightPlan, Error, string>({
    mutationFn: async (prompt: string) => {
      const res = await fetch("/api/concierge", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ prompt }),
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
