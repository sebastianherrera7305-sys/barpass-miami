"use client";

import Link from "next/link";
import { motion } from "framer-motion";
import { Sparkles, ArrowRight } from "lucide-react";
import { Card } from "@/components/ui/card";
import { formatUSD } from "@/lib/utils";
import type { NightPlan } from "@/types";

/**
 * Rendered itinerary — timeline of stops with deep links into venue pages.
 * Animates in stop-by-stop so the plan feels "built" for the user.
 */
export function NightPlanCard({ plan }: { plan: NightPlan }) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 16 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.4 }}
    >
      <Card className="overflow-hidden">
        {/* Header */}
        <div className="border-b border-border-subtle bg-gradient-to-r from-amber-brand/8 to-transparent px-6 py-5">
          <h3 className="text-lg font-bold">{plan.title}</h3>
          <p className="mt-1 text-sm text-text-secondary">{plan.summary}</p>
        </div>

        {/* Timeline */}
        <ol className="space-y-0 px-6 py-4">
          {plan.stops.map((stop, i) => (
            <motion.li
              key={`${stop.venueSlug}-${i}`}
              initial={{ opacity: 0, x: -12 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ delay: 0.15 * i, duration: 0.35 }}
              className="relative flex gap-4 pb-6 last:pb-2"
            >
              {/* Rail */}
              <div className="flex flex-col items-center">
                <span className="mt-1 h-2.5 w-2.5 rounded-full bg-amber-brand shadow-[0_0_8px_rgba(235,184,71,0.6)]" />
                {i < plan.stops.length - 1 && (
                  <span className="mt-1 w-px flex-1 bg-border-subtle" />
                )}
              </div>

              <div className="min-w-0 flex-1">
                <p className="text-[11px] font-bold uppercase tracking-widest text-amber-brand">
                  {stop.time}
                </p>
                <Link
                  href={`/venues/${stop.venueSlug}`}
                  className="group mt-0.5 inline-flex items-center gap-1 text-[15px] font-bold hover:text-amber-bright"
                >
                  {stop.venueName}
                  <ArrowRight className="h-3.5 w-3.5 opacity-0 transition-opacity group-hover:opacity-100" />
                </Link>
                <p className="mt-1 text-sm leading-relaxed text-text-secondary">
                  {stop.note}
                </p>
                <p className="mt-1 text-xs text-text-tertiary">
                  ~{formatUSD(stop.estimatedSpend)}
                </p>
              </div>
            </motion.li>
          ))}
        </ol>

        {/* Footer */}
        <div className="flex items-start justify-between gap-4 border-t border-border-subtle px-6 py-4">
          <p className="flex items-start gap-2 text-xs leading-relaxed text-text-secondary">
            <Sparkles className="mt-0.5 h-3.5 w-3.5 shrink-0 text-amber-brand" />
            {plan.insiderTip}
          </p>
          <p className="shrink-0 text-right">
            <span className="block text-[10px] uppercase tracking-widest text-text-tertiary">
              Est. total
            </span>
            <span className="text-lg font-black text-amber-brand">
              {formatUSD(plan.totalEstimate)}
            </span>
          </p>
        </div>
      </Card>
    </motion.div>
  );
}
