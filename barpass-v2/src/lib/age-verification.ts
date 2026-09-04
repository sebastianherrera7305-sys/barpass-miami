import { NextResponse } from "next/server";
import type { SupabaseClient } from "@supabase/supabase-js";

/**
 * Server-side 21+ enforcement for anything alcohol-adjacent (Apple
 * Guideline 1.3 — this app centers on alcohol access).
 *
 * Audit finding, 2026-09-05: verification only ever existed client-side
 * (AgeGateService, a plain UserDefaults flag) plus a DB trigger
 * (`enforce_adult_birthdate`) that blocks setting a birthdate showing under
 * 18 — neither actually stops a purchase from going through server-side for
 * someone who never passed the gate at all (no birthdate on file) or who
 * cleared 18 but not the actual 21+ bar this app needs. This is the real
 * enforcement point every purchase-adjacent route should call before
 * moving money: no verified 21+ birthdate on file in `profiles`, no charge.
 */
export function isAtLeast21(birthdateStr: string): boolean {
  const birthdate = new Date(birthdateStr);
  if (Number.isNaN(birthdate.getTime())) return false;
  const now = new Date();
  let age = now.getUTCFullYear() - birthdate.getUTCFullYear();
  const hasHadBirthdayThisYear =
    now.getUTCMonth() > birthdate.getUTCMonth() ||
    (now.getUTCMonth() === birthdate.getUTCMonth() && now.getUTCDate() >= birthdate.getUTCDate());
  if (!hasHadBirthdayThisYear) age -= 1;
  return age >= 21;
}

/** Returns a ready 403 NextResponse if the user isn't verified 21+, or
 * `null` when they are — call sites just do
 * `const denied = await requireAgeVerified21(supabase, user.id); if (denied) return denied;` */
export async function requireAgeVerified21(
  supabase: SupabaseClient,
  userId: string,
): Promise<NextResponse | null> {
  const { data: profile } = await supabase
    .from("profiles")
    .select("birthdate")
    .eq("id", userId)
    .maybeSingle();
  if (!profile?.birthdate || !isAtLeast21(profile.birthdate)) {
    return NextResponse.json({ error: "age_verification_required" }, { status: 403 });
  }
  return null;
}
