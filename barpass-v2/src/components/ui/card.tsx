import { cn } from "@/lib/utils";
import type { HTMLAttributes } from "react";

/** Base surface card — the building block of every list and detail page. */
export function Card({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      className={cn(
        "rounded-[20px] bg-surface border border-border-subtle",
        className,
      )}
      {...props}
    />
  );
}
