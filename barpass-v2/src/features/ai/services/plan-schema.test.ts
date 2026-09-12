import { describe, expect, it } from "vitest";
import { conciergeChatRequestSchema, trimConciergeHistory } from "./plan-schema";

const turn = (role: "user" | "assistant", content: string) => ({ role, content });

describe("conciergeChatRequestSchema", () => {
  it("accepts a long chat history instead of 400-ing the whole conversation", () => {
    // The iOS app sends every persisted turn; a 41-message chat used to be
    // rejected on every subsequent turn.
    const messages = Array.from({ length: 120 }, (_, i) => turn(i % 2 ? "assistant" : "user", `turn ${i}`));
    expect(conciergeChatRequestSchema.safeParse({ messages }).success).toBe(true);
  });

  it("still rejects an empty history and an unknown role", () => {
    expect(conciergeChatRequestSchema.safeParse({ messages: [] }).success).toBe(false);
    expect(conciergeChatRequestSchema.safeParse({ messages: [{ role: "system", content: "x" }] }).success).toBe(false);
  });
});

describe("trimConciergeHistory", () => {
  it("keeps the newest turns up to the turn cap, in order", () => {
    const messages = Array.from({ length: 50 }, (_, i) => turn(i % 2 ? "assistant" : "user", `t${i}`));
    const out = trimConciergeHistory(messages, { maxTurns: 6 });
    expect(out.map((m) => m.content)).toEqual(["t44", "t45", "t46", "t47", "t48", "t49"]);
  });

  it("stops adding older turns once the character budget is spent", () => {
    const messages = [turn("user", "a".repeat(100)), turn("assistant", "b".repeat(100)), turn("user", "c".repeat(50))];
    const out = trimConciergeHistory(messages, { maxChars: 160 });
    expect(out.map((m) => m.content[0])).toEqual(["b", "c"]);
  });

  it("always keeps the last message, truncated if it alone exceeds the budget", () => {
    const out = trimConciergeHistory([turn("user", "old"), turn("user", "x".repeat(500))], { maxChars: 100 });
    expect(out).toHaveLength(1);
    expect(out[0].content).toHaveLength(100);
  });

  it("returns an untouched copy when the history already fits", () => {
    const messages = [turn("user", "hola"), turn("assistant", "qué tal"), turn("user", "un rooftop")];
    expect(trimConciergeHistory(messages)).toEqual(messages);
  });
});
