import type { LucideIcon } from "lucide-react";

interface FactRowProps {
  label: string;
  value: string | number;
  capitalize?: boolean;
  icon?: LucideIcon;
}

export function FactRow({ label, value, capitalize = false, icon: Icon }: FactRowProps) {
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
