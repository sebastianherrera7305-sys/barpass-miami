import type { LucideIcon } from "lucide-react";

interface FactRowProps {
  label: string;
  value: string | number | null | undefined;
  capitalize?: boolean;
  icon?: LucideIcon;
}

/**
 * Renders nothing when there is no value. dress_code, parking,
 * best_arrival_time and peak_hours were NOT NULL columns carrying one
 * identical fabricated value across 175 seeded rows; those were cleared on
 * 2026-09-01, so most venues now have nothing to show here and an unguarded
 * row would render a label with a blank beside it.
 */
export function FactRow({ label, value, capitalize = false, icon: Icon }: FactRowProps) {
  if (value === null || value === undefined) return null;
  if (typeof value === "string" && value.trim() === "") return null;

  return (
    <div className="flex items-start justify-between gap-3">
      <div className="flex items-center gap-2 text-text-secondary">
        {Icon ? <Icon className="h-3.5 w-3.5" /> : null}
        <span>{label}</span>
      </div>
      <span className={`text-right font-medium text-white ${capitalize ? "capitalize" : ""}`}>
        {value}
      </span>
    </div>
  );
}
