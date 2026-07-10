"use client";

import { useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { Sparkles, SendHorizonal, LoaderCircle, Gem } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useConcierge } from "../hooks/use-concierge";
import { CONCIERGE_SUGGESTIONS } from "../constants/suggestions";
import { NightPlanCard } from "./night-plan-card";

export function ConciergePanel() {
  const [prompt, setPrompt] = useState("");
  const concierge = useConcierge();

  const submit = (text: string) => {
    const clean = text.trim();
    if (!clean || concierge.isPending) return;
    concierge.mutate(clean);
  };

  return (
    <div className="mx-auto w-full max-w-2xl space-y-6">
      <motion.div
        initial={{ opacity: 0, y: 8 }}
        animate={{ opacity: 1, y: 0 }}
        className="text-center"
      >
        <span className="mx-auto mb-3 grid h-12 w-12 place-items-center rounded-full bg-amber-brand/15">
          <Gem className="h-6 w-6 text-amber-brand" />
        </span>
        <h2 className="text-xl font-black tracking-tight">
          Remy, your nightlife concierge
        </h2>
        <p className="mt-1 text-sm text-text-secondary">
          Tell me your budget, vibe, and what you&apos;re after — I&apos;ll build the perfect Miami night.
        </p>
      </motion.div>

      <div className="relative">
        <textarea
          value={prompt}
          onChange={(e) => setPrompt(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.shiftKey) {
              e.preventDefault();
              submit(prompt);
            }
          }}
          rows={3}
          placeholder='e.g. "First date, $100, we love rooftops"'
          className="w-full resize-none rounded-[20px] border border-border-subtle bg-surface px-5 py-4 pr-14 text-[15px] placeholder:text-text-tertiary focus:border-amber-brand/50 focus:outline-none"
        />
        <button
          onClick={() => submit(prompt)}
          disabled={concierge.isPending || !prompt.trim()}
          aria-label="Build my night"
          className="absolute bottom-4 right-4 grid h-9 w-9 place-items-center rounded-full bg-amber-brand text-black transition-all hover:brightness-110 disabled:opacity-30"
        >
          {concierge.isPending ? (
            <LoaderCircle className="h-4 w-4 animate-spin" />
          ) : (
            <SendHorizonal className="h-4 w-4" />
          )}
        </button>
      </div>

      {!concierge.data && !concierge.isPending && (
        <div className="flex flex-wrap gap-2">
          {CONCIERGE_SUGGESTIONS.map((s) => (
            <button
              key={s}
              onClick={() => {
                setPrompt(s);
                submit(s);
              }}
              className="rounded-full border border-border-subtle bg-surface px-4 py-2 text-[13px] text-text-secondary transition-colors hover:border-amber-brand/40 hover:text-amber-brand"
            >
              {s}
            </button>
          ))}
        </div>
      )}

      <AnimatePresence>
        {concierge.isPending && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="flex items-center gap-3 rounded-[20px] border border-border-subtle bg-surface px-6 py-5"
          >
            <Sparkles className="h-5 w-5 animate-pulse text-amber-brand" />
            <div>
              <p className="text-sm font-semibold">Remy is working on it.</p>
              <p className="text-xs text-text-tertiary">
                Calling in favors, checking guest lists, building your perfect itinerary…
              </p>
            </div>
          </motion.div>
        )}
      </AnimatePresence>

      {concierge.isError && (
        <motion.div
          initial={{ opacity: 0, y: 8 }}
          animate={{ opacity: 1, y: 0 }}
          className="rounded-[20px] border border-danger/20 bg-danger/5 px-6 py-4"
        >
          <p className="text-sm text-danger">
            {concierge.error.message === "ai_not_configured"
              ? "Remy isn't connected yet — add OPENAI_API_KEY to the concierge."
              : "Couldn't build your plan. Try again in a moment."}
          </p>
          <Button
            variant="ghost"
            size="sm"
            className="mt-2"
            onClick={() => submit(prompt)}
          >
            Try again
          </Button>
        </motion.div>
      )}

      {concierge.data && (
        <>
          <NightPlanCard plan={concierge.data} />
          <div className="text-center">
            <Button
              variant="ghost"
              size="sm"
              onClick={() => {
                concierge.reset();
                setPrompt("");
              }}
            >
              Plan another night
            </Button>
          </div>
        </>
      )}
    </div>
  );
}
