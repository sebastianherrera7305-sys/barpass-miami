"use client";

import { useCallback, useRef, useState } from "react";
import { nightPlanSchema, type ValidatedNightPlan } from "../services/plan-schema";

/**
 * Client-side chat state for the AI Concierge ("Remy").
 * Streams raw text from POST /api/concierge and, once a message's stream
 * closes, checks whether it ends in a ```json ... ``` fenced NightPlan
 * block — if so, that block is parsed out and validated, and the message
 * carries a `plan` alongside its visible chat text (the fence itself is
 * stripped from what's shown).
 */
export interface ConciergeMessage {
  id: string;
  role: "user" | "assistant";
  /** Visible chat text — for an in-flight assistant message this grows token by token. */
  text: string;
  plan?: ValidatedNightPlan;
  /** Quick-reply chips (2-4 short options) parsed out of a ```options fence
   * — tap-first alternative to typing, for questions with a small set of
   * natural answers. */
  options?: string[];
  isStreaming?: boolean;
  /** True from the moment the model shows ANY sign of life until real text starts arriving. */
  isThinking?: boolean;
}

// Control bytes the route injects into the raw text stream — never occur in
// real model output. \x01 = reasoning started ("thinking"), \x02 = real
// content started (everything after is the actual message).
const THINKING_MARK = "\x01";
const CONTENT_MARK = "\x02";

const PLAN_FENCE = /```json\s*([\s\S]*?)```\s*$/;
const OPTIONS_FENCE = /```options\s*([\s\S]*?)```\s*$/;
const OPEN_FENCE = /```(json|options)[\s\S]*$/;

/** While a message is still streaming, an unterminated ```json/```options
 * fence would otherwise show as raw, half-typed text in the chat bubble —
 * cut it off at the fence's start instead so the plan card or option chips
 * take over once it's ready. */
function hideOpenFence(text: string): string {
  return text.replace(OPEN_FENCE, "").trim();
}

function splitPlanFence(raw: string): { text: string; plan?: ValidatedNightPlan; options?: string[] } {
  const planMatch = raw.match(PLAN_FENCE);
  if (planMatch) {
    try {
      const result = nightPlanSchema.safeParse(JSON.parse(planMatch[1]));
      if (result.success) {
        return { text: raw.slice(0, planMatch.index).trim(), plan: result.data };
      }
    } catch {
      // Fence wasn't valid/complete JSON yet (or model glitched) — fall
      // through and just show the raw text, fence included.
    }
  }
  const optionsMatch = raw.match(OPTIONS_FENCE);
  if (optionsMatch) {
    try {
      const parsed = JSON.parse(optionsMatch[1]);
      if (Array.isArray(parsed) && parsed.every((o) => typeof o === "string") && parsed.length > 0) {
        return { text: raw.slice(0, optionsMatch.index).trim(), options: parsed.slice(0, 4) };
      }
    } catch {
      // Same — malformed options fence, show the raw text instead.
    }
  }
  return { text: raw };
}

export function useConciergeChat() {
  const [messages, setMessages] = useState<ConciergeMessage[]>([]);
  const [isSending, setIsSending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const idCounter = useRef(0);
  const nextId = () => `m${++idCounter.current}`;

  const send = useCallback(
    async (text: string, city?: string) => {
      const clean = text.trim();
      if (!clean || isSending) return;
      setError(null);

      const userMsg: ConciergeMessage = { id: nextId(), role: "user", text: clean };
      const assistantId = nextId();
      const history = [...messages, userMsg];
      setMessages([...history, { id: assistantId, role: "assistant", text: "", isStreaming: true }]);
      setIsSending(true);

      try {
        const res = await fetch("/api/concierge", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            messages: history.map((m) => ({ role: m.role, content: m.text })),
            city,
          }),
        });

        if (!res.ok || !res.body) {
          const body = (await res.json().catch(() => null)) as { error?: string } | null;
          throw new Error(body?.error ?? "concierge_failed");
        }

        const reader = res.body.getReader();
        const decoder = new TextDecoder();
        let raw = "";
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          raw += decoder.decode(value, { stream: true });

          const contentIdx = raw.indexOf(CONTENT_MARK);
          if (contentIdx === -1) {
            // Still in the "thinking" phase — nothing user-facing to show
            // yet, just the live indicator.
            if (raw.includes(THINKING_MARK)) {
              setMessages((prev) =>
                prev.map((m) => (m.id === assistantId ? { ...m, isThinking: true, isStreaming: true } : m)),
              );
            }
            continue;
          }

          const visible = raw.slice(contentIdx + 1);
          const live = hideOpenFence(visible);
          setMessages((prev) =>
            prev.map((m) =>
              m.id === assistantId
                ? { ...m, text: live, isThinking: false, isStreaming: true }
                : m,
            ),
          );
        }
        raw = raw.includes(CONTENT_MARK) ? raw.slice(raw.indexOf(CONTENT_MARK) + 1) : raw;

        const { text: finalText, plan, options } = splitPlanFence(raw);
        setMessages((prev) =>
          prev.map((m) =>
            m.id === assistantId
              ? { ...m, text: finalText || "…", plan, options, isStreaming: false }
              : m,
          ),
        );
      } catch (e) {
        setMessages((prev) => prev.filter((m) => m.id !== assistantId));
        setError(e instanceof Error ? e.message : "concierge_failed");
      } finally {
        setIsSending(false);
      }
    },
    [messages, isSending],
  );

  const reset = useCallback(() => {
    setMessages([]);
    setError(null);
  }, []);

  return { messages, send, isSending, error, reset };
}
