import type { Metadata } from "next";
import { Sparkles } from "lucide-react";
import { ConciergePanel } from "@/features/ai/components/concierge-panel";

export const metadata: Metadata = {
  title: "AI Concierge",
  description:
    "Tell the BarPass Concierge your budget, mood and vibe — get a personalized Miami nightlife itinerary in seconds.",
};

/**
 * The Concierge page — the identity of BarPass.
 * Minimal chrome; the conversation IS the interface.
 */
export default function ConciergePage() {
  return (
    <div className="mx-auto max-w-2xl px-6 pt-12">
      <div className="mb-10 text-center">
        <span className="mx-auto grid h-14 w-14 place-items-center rounded-full bg-amber-brand/12">
          <Sparkles className="h-6 w-6 text-amber-brand" />
        </span>
        <h1 className="mt-4 text-3xl font-black tracking-tight">
          Your night, planned.
        </h1>
        <p className="mx-auto mt-2 max-w-md text-[15px] text-text-secondary">
          Budget, mood, music, occasion — tell me anything. I&rsquo;ll build
          the itinerary a local would.
        </p>
      </div>

      <ConciergePanel />
    </div>
  );
}
