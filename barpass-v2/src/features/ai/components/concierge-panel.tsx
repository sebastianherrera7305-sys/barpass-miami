"use client";

import { useEffect, useRef, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { SendHorizonal, Gem } from "lucide-react";
import { useConciergeChat } from "../hooks/use-concierge-chat";
import { CONCIERGE_SUGGESTIONS } from "../constants/suggestions";
import { NightPlanCard } from "./night-plan-card";

/**
 * Remy — full chat interface, not a one-shot "generate a plan" form.
 * Streams tokens in as they arrive so the ~30-70s round trip to the model
 * reads as a real conversation in progress, not a silent, possibly-broken
 * wait. A message can carry a `plan` (parsed out of a trailing ```json
 * fence) which renders as a rich itinerary card below the chat bubble.
 */
export function ConciergePanel() {
  const [input, setInput] = useState("");
  const chat = useConciergeChat();
  const bottomRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [chat.messages]);

  const submit = (text: string) => {
    const clean = text.trim();
    if (!clean || chat.isSending) return;
    setInput("");
    void chat.send(clean, "Miami");
  };

  const isEmpty = chat.messages.length === 0;

  return (
    <div className="mx-auto flex w-full max-w-2xl flex-col">
      {isEmpty && (
        <motion.div
          initial={{ opacity: 0, y: 8 }}
          animate={{ opacity: 1, y: 0 }}
          className="pb-6 text-center"
        >
          <span className="mx-auto mb-3 grid h-12 w-12 place-items-center rounded-full bg-amber-brand/15">
            <Gem className="h-6 w-6 text-amber-brand" />
          </span>
          <h2 className="text-xl font-black tracking-tight">
            Remy, your nightlife concierge
          </h2>
          <p className="mt-1 text-sm text-text-secondary">
            Tell me your budget, vibe, and what you&apos;re after — let&apos;s figure out tonight together.
          </p>
        </motion.div>
      )}

      <div className="flex-1 space-y-5 pb-4">
        <AnimatePresence initial={false}>
          {chat.messages.map((m) => (
            <motion.div
              key={m.id}
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              className={m.role === "user" ? "flex justify-end" : "flex justify-start"}
            >
              <div className={m.role === "user" ? "max-w-[85%]" : "w-full max-w-[85%]"}>
                {m.role === "user" ? (
                  <div className="rounded-[18px] rounded-br-sm bg-amber-brand px-4 py-2.5 text-[14px] font-medium text-black">
                    {m.text}
                  </div>
                ) : m.isThinking ? (
                  <div className="flex items-center gap-2 rounded-[18px] rounded-bl-sm border border-border-subtle bg-surface px-4 py-3">
                    <span className="flex gap-1">
                      <span className="h-1.5 w-1.5 animate-bounce rounded-full bg-amber-brand [animation-delay:-0.3s]" />
                      <span className="h-1.5 w-1.5 animate-bounce rounded-full bg-amber-brand [animation-delay:-0.15s]" />
                      <span className="h-1.5 w-1.5 animate-bounce rounded-full bg-amber-brand" />
                    </span>
                    <span className="text-[13px] text-text-tertiary">Remy is thinking…</span>
                  </div>
                ) : (
                  <div className="space-y-3">
                    {(m.text || m.isStreaming) && (
                      <div className="rounded-[18px] rounded-bl-sm border border-border-subtle bg-surface px-4 py-2.5 text-[14px] leading-relaxed">
                        {m.text}
                        {m.isStreaming && (
                          <span className="ml-0.5 inline-block h-3.5 w-1.5 animate-pulse bg-amber-brand align-middle" />
                        )}
                      </div>
                    )}
                    {m.plan && <NightPlanCard plan={m.plan} />}
                  </div>
                )}
              </div>
            </motion.div>
          ))}
        </AnimatePresence>
        <div ref={bottomRef} />
      </div>

      {chat.error && (
        <motion.div
          initial={{ opacity: 0, y: 8 }}
          animate={{ opacity: 1, y: 0 }}
          className="mb-4 rounded-[16px] border border-danger/20 bg-danger/5 px-5 py-3 text-sm text-danger"
        >
          {chat.error === "ai_not_configured"
            ? "Remy isn't connected yet."
            : "Something interrupted Remy — try sending that again."}
        </motion.div>
      )}

      {isEmpty && (
        <div className="mb-4 flex flex-wrap gap-2">
          {CONCIERGE_SUGGESTIONS.map((s) => (
            <button
              key={s}
              onClick={() => submit(s)}
              className="rounded-full border border-border-subtle bg-surface px-4 py-2 text-[13px] text-text-secondary transition-colors hover:border-amber-brand/40 hover:text-amber-brand"
            >
              {s}
            </button>
          ))}
        </div>
      )}

      <div className="sticky bottom-4 z-10">
        <div className="relative">
          <textarea
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter" && !e.shiftKey) {
                e.preventDefault();
                submit(input);
              }
            }}
            rows={1}
            placeholder={isEmpty ? 'e.g. "First date, $100, we love rooftops"' : "Ask Remy anything…"}
            className="w-full resize-none rounded-full border border-border-subtle bg-surface px-5 py-3.5 pr-14 text-[14px] placeholder:text-text-tertiary focus:border-amber-brand/50 focus:outline-none"
          />
          <button
            onClick={() => submit(input)}
            disabled={chat.isSending || !input.trim()}
            aria-label="Send"
            className="absolute bottom-2 right-2 grid h-9 w-9 place-items-center rounded-full bg-amber-brand text-black transition-all hover:brightness-110 disabled:opacity-30"
          >
            <SendHorizonal className="h-4 w-4" />
          </button>
        </div>
      </div>
    </div>
  );
}
