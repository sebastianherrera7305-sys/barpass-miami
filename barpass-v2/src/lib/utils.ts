import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

/**
 * Merge Tailwind classes with correct precedence.
 * The standard `cn` helper used by every component in the codebase.
 */
export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

/**
 * Format a dollar amount for display ("$20", "$1,250"). Some venue rows
 * are missing pricing data (e.g. avg_spend not yet backfilled) despite the
 * column being typed as non-null — falls back to "—" instead of crashing
 * Intl.NumberFormat on undefined during static generation.
 */
export function formatUSD(amount: number | null | undefined): string {
  if (amount == null) return "—";
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    maximumFractionDigits: 0,
  }).format(amount);
}

/**
 * "10:30 PM" from a 24h "22:30" string. Handles "24:00" as Midnight.
 * Venue hours aren't always real times — rows enriched from Google carry
 * placeholders like "Ver Google Maps" — so anything unparseable is passed
 * through as-is rather than crashing on a missing minutes component.
 */
export function formatTime(time24: string | null | undefined): string {
  if (!time24) return "—";
  const [h, m] = time24.split(":").map(Number);
  if (!Number.isFinite(h) || !Number.isFinite(m)) return time24;
  if (h === 24 && m === 0) return "Midnight";
  const suffix = h >= 12 ? "PM" : "AM";
  const hour = h % 12 || 12;
  return `${hour}:${m.toString().padStart(2, "0")} ${suffix}`;
}

/**
 * "10:00 PM – 5:00 AM" from an open/close pair.
 *
 * ~17% of venues (171/1000 as of 2026-08-31) never got their hours parsed
 * during Google enrichment: open_time and close_time both hold the same
 * raw string, either a placeholder ("Ver Google Maps") or a whole rendered
 * range ("Friday: 4:00 PM – 5:00 AM"). Joining those two identical values
 * with a dash would print the range twice, so an equal pair is shown once.
 */
export function formatHoursRange(
  openTime: string | null | undefined,
  closeTime: string | null | undefined,
): string {
  const open = formatTime(openTime);
  const close = formatTime(closeTime);
  return open === close ? open : `${open} – ${close}`;
}
