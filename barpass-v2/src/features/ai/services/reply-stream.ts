import type { Venue } from "@/types";
import { groundPlanBlock } from "./plan-grounding";
import { nightPlanSchema } from "./plan-schema";

/**
 * The transform between the model's raw content deltas and the bytes a
 * client actually renders. Extracted from the route (2026-09-13) so the
 * rules below are unit-testable instead of only observable in production.
 *
 * It exists because of one class of TestFlight complaint — "escribió la
 * respuesta en código", "chats look weird" — which is always the same
 * failure: the model emitted something that BOTH clients fall back to
 * rendering as literal text. Three distinct ways that happens, all handled
 * here:
 *
 * 1. A fenced block that isn't last. The web parses a plan with
 *    /```json\s*([\s\S]*?)```\s*$/ — anchored at end-of-string. The model
 *    is told to put "nothing after" the block and sometimes signs off
 *    anyway ("¡Que la disfrutes!"), and the old transform streamed that
 *    trailing line straight after the fence, so the anchor missed and the
 *    ENTIRE JSON object rendered in the chat bubble. A block is now held
 *    and emitted LAST, after all prose, whatever order the model used.
 *
 * 2. A fenced plan that doesn't validate. Neither client renders a card it
 *    can't decode — the web shows the raw fence, iOS returns the whole raw
 *    string. The block is validated here against the very schema the web
 *    uses, after grounding has repaired what is repairable; one that still
 *    fails is dropped, because prose alone beats a wall of JSON.
 *
 * 3. Markup the prompt forbids and the model emits anyway. Measured against
 *    production on 2026-09-13: "donde puedo salir hoy en Miami" came back
 *    as a "- 9:45 PM: ..." markdown bullet list with two-space hard breaks,
 *    and "plan something" wrote its quick replies inline as
 *    `Options: ["Weekend", "Weekday"]` — a literal JSON array in the
 *    bubble. Bold/bullets/headings are stripped, and an inline options
 *    array is promoted to the real ```options fence it was meant to be, so
 *    the user gets tappable chips instead of punctuation.
 *
 * 4. A block with no tag on its fence, or no fence at all. Build 84's
 *    "It's writhing in code" (2026-10-08) was a plan opened with a bare
 *    ``` — the tag is the only thing either client keys on, so the object
 *    streamed into the bubble key by key. Both shapes are now recognised
 *    and re-emitted with the fence the prompt asked for, which is also why
 *    this belongs here and not in the clients: one fix, every build already
 *    in testers' hands included.
 *
 * Nothing here throws and nothing blocks the stream: prose is forwarded as
 * it arrives, minus a few held-back characters at the tail that might be
 * the start of a marker.
 */

const JSON_FENCE = "```json";
const OPTIONS_FENCE = "```options";
const BARE_FENCE = "```";
const FENCE_TAGS = [JSON_FENCE, OPTIONS_FENCE] as const;
const LONGEST_TAG = Math.max(...FENCE_TAGS.map((t) => t.length));

/** What a fence turned out to be once enough of it has arrived to tell.
 * "wait" means the classifying character hasn't streamed in yet. */
type FenceKind = "json" | "options";
type Classified = { kind: FenceKind; tag: string } | "prose" | "wait";

/**
 * What the model opened, given everything that follows the three backticks.
 *
 * The tag is optional to the model even though the prompt spells it out:
 * TestFlight build 84, 2026-10-08 ("It's writhing in code") was a plan block
 * opened with a bare ``` — no `json` — so neither this transform nor either
 * client recognised it and the whole object rendered in the chat bubble.
 * A bare fence is classified by its first real character instead, which is
 * the same thing a human reads it by: `{` opens the plan, `[` the options.
 */
function classifyFence(after: string): Classified {
  if (after.startsWith("json")) return { kind: "json", tag: JSON_FENCE };
  if (after.startsWith("options")) return { kind: "options", tag: OPTIONS_FENCE };
  // The tag itself may still be arriving one character at a time.
  if (after.length > 0 && ("json".startsWith(after) || "options".startsWith(after))) return "wait";
  const first = after.match(/^\s*(\S)/);
  if (!first) return "wait";
  if (first[1] === "{") return { kind: "json", tag: BARE_FENCE };
  if (first[1] === "[") return { kind: "options", tag: BARE_FENCE };
  // A code fence around something that is neither block — leave it be.
  return "prose";
}

/**
 * Where an UNFENCED plan object starts in `text`, or -1.
 *
 * The other half of the same failure: the model drops the fence entirely and
 * writes the object straight into its reply. Recognised narrowly — a brace
 * that opens a line (or the reply) and is followed by a JSON key — because
 * the cost of a false positive is deleting the model's actual words. Remy's
 * prose never contains a brace; the prompt asks for plain text.
 *
 * A brace whose key hasn't arrived yet still counts, so the caller holds it
 * back instead of streaming half an object into the bubble; once the next
 * character proves it was ordinary prose, it stops matching and flows on.
 */
function unfencedPlanStart(text: string): number {
  for (let i = 0; i < text.length; i++) {
    if (text[i] !== "{") continue;
    if (i > 0 && !/\s/.test(text[i - 1])) continue;
    if (/^\{\s*("|$)/.test(text.slice(i))) return i;
  }
  return -1;
}

/**
 * Index just past the closing brace of the JSON object starting at `from`,
 * or -1 while it is still arriving. Counts depth outside of strings so a
 * brace inside a venue name or a note can't end the object early.
 */
function jsonObjectEnd(text: string, from: number): number {
  let depth = 0;
  let inString = false;
  let escaped = false;
  for (let i = from; i < text.length; i++) {
    const c = text[i];
    if (inString) {
      if (escaped) escaped = false;
      else if (c === "\\") escaped = true;
      else if (c === '"') inString = false;
      continue;
    }
    if (c === '"') inString = true;
    else if (c === "{") depth++;
    else if (c === "}" && --depth === 0) return i + 1;
  }
  return -1;
}

/** What the model writes instead of a fence when it ignores the format:
 * `Options: ["Weekend", "Weekday"]`, either on its own line or tacked onto
 * the end of the question ("...weekend or weekday? Options: [...]", measured
 * in production 2026-09-13). Matched once the closing bracket has arrived. */
const INLINE_OPTIONS_CLOSED = /(^|\s)(?:options|opciones)[ \t]*:[ \t]*(\[[^\]\n]*\])[ \t]*\.?[ \t]*(?=\n|$)/i;
const OPTIONS_WORDS = ["options", "opciones"];
const isWordChar = (c: string | undefined) => c !== undefined && /[a-z0-9]/i.test(c);

/**
 * How many characters at the tail belong to an inline options array that
 * hasn't closed yet, and so must not be streamed into the bubble half-typed.
 *
 * Deliberately not one regex: an expression with every part optional matches
 * the empty string at the first space and would hold the entire rest of the
 * line on EVERY reply, turning a streaming answer into one that appears all
 * at once. The word has to really be there — either complete, or as a prefix
 * still arriving at the very tail, and in both cases at a word boundary.
 */
function inlineOptionsHold(pending: string): number {
  const tail = pending.slice(Math.max(0, pending.length - 400));
  const lower = tail.toLowerCase();
  let hold = 0;
  for (const word of OPTIONS_WORDS) {
    for (let i = lower.indexOf(word); i !== -1; i = lower.indexOf(word, i + 1)) {
      if (isWordChar(tail[i - 1])) continue;
      const rest = tail.slice(i + word.length);
      // The line finished, or the array already closed: nothing to hold —
      // clean() deals with it.
      if (rest.includes("\n") || /^[ \t]*:?[ \t]*\[[^\]\n]*\]/.test(rest)) continue;
      if (/^[ \t]*:?[ \t]*\[?[^\]\n]*$/.test(rest)) hold = Math.max(hold, tail.length - i);
    }
    // "...Optio" — the word itself is still being typed.
    for (let n = Math.min(word.length - 1, tail.length); n > 0; n--) {
      if (!word.startsWith(lower.slice(lower.length - n))) continue;
      if (!isWordChar(tail[tail.length - n - 1])) hold = Math.max(hold, n);
      break;
    }
  }
  return Math.min(hold, pending.length);
}

/** Markup the chat bubbles render literally, so it must never reach them.
 * The plan card's own fields are cleaned separately, in groundPlanBlock. */
export function sanitizeProse(text: string): string {
  return (
    text
      .replace(/\*\*/g, "")
      // "### Tonight" / "- 9:45 PM" / "• Astra" at the start of a line.
      .replace(/(^|\n)[ \t]*#{1,6}[ \t]+/g, "$1")
      .replace(/(^|\n)[ \t]*[-*•][ \t]+/g, "$1")
      // Markdown's two-space hard break — invisible in a renderer, trailing
      // whitespace everywhere else.
      .replace(/[ \t]+(?=\n)/g, "")
  );
}

/** Characters at the tail of `pending` that might be the start of something
 * we have to act on once more text arrives, and so must not be emitted yet. */
function holdLength(pending: string): number {
  let hold = 0;
  // A partial "```json" / "```options".
  for (let n = Math.min(LONGEST_TAG - 1, pending.length); n > 0; n--) {
    const tail = pending.slice(pending.length - n);
    if (FENCE_TAGS.some((t) => t.startsWith(tail))) {
      hold = n;
      break;
    }
  }
  // A partial bold marker. Both stars must be held: when a token was
  // exactly "**", holding one emitted the other alone, so "**Sugar**"
  // streamed as "*Sugar*" — a stray star the iOS bubble shows literally.
  if (pending.endsWith("**")) hold = Math.max(hold, 2);
  else if (pending.endsWith("*")) hold = Math.max(hold, 1);
  // A line-start marker mid-arrival: "\n", "\n- ", "\n#".
  const marker = pending.match(/\n[ \t]*[-*•#>]{0,6}[ \t]*$/);
  if (marker) hold = Math.max(hold, marker[0].length);
  // Trailing spaces that may turn out to be a hard break.
  const trailingSpace = pending.match(/[ \t]+$/);
  if (trailingSpace) hold = Math.max(hold, trailingSpace[0].length);
  hold = Math.max(hold, inlineOptionsHold(pending));
  return Math.min(hold, pending.length);
}

export interface ReplyTransformOptions {
  shortlist: Venue[];
  /** Why a block was dropped — wired to console.error by the route. */
  onDrop?: (reason: string) => void;
}

export interface ReplyTransform {
  /** Feed one content delta; returns the text to write to the client now. */
  push(piece: string): string;
  /** End of stream: returns the remaining prose followed by the held block. */
  flush(): string;
}

export function createReplyTransform({ shortlist, onDrop }: ReplyTransformOptions): ReplyTransform {
  let pending = "";
  /** Inside a fence: the raw text from the opening tag onward. */
  let fenceBuffer: string | null = null;
  /** The literal opener, so the closing ``` is never found inside it. */
  let fenceTag: string | null = null;
  /** What the open fence turned out to be — not the same thing as its tag
   * any more, now that a bare ``` can open either block. */
  let fenceKind: FenceKind | null = null;
  /** The one finished block, emitted last. A message carries at most one;
   * if the model sends both, the plan wins (it's the richer answer). */
  let heldPlan: string | null = null;
  let heldOptions: string | null = null;

  /** A closed ```json block: ground it to real catalog venues, then hold it
   * only if it validates as the card the clients will actually render. */
  const takePlan = (inner: string) => {
    const grounded = groundPlanBlock(inner.trim(), shortlist);
    if (!grounded) {
      onDrop?.("plan block had no real venues after grounding");
      return;
    }
    let parsed: unknown;
    try {
      parsed = JSON.parse(grounded);
    } catch {
      onDrop?.("plan block was not valid JSON");
      return;
    }
    if (!nightPlanSchema.safeParse(parsed).success) {
      onDrop?.("plan block failed nightPlanSchema — would have rendered as raw JSON");
      return;
    }
    heldPlan = grounded;
  };

  /** A closed ```options block, or a rescued inline one. Held only if it is
   * the array of short strings the chips are built from. */
  const takeOptions = (inner: string) => {
    let parsed: unknown;
    try {
      parsed = JSON.parse(inner.trim());
    } catch {
      onDrop?.("options block was not valid JSON");
      return;
    }
    if (!Array.isArray(parsed) || parsed.length === 0 || !parsed.every((o) => typeof o === "string" && o.trim())) {
      onDrop?.("options block was not a non-empty array of strings");
      return;
    }
    heldOptions = JSON.stringify(parsed.slice(0, 4));
  };

  /** Prose on its way out: strip markup, and promote an inline options array
   * to the fence it should have been. */
  const clean = (text: string): string => {
    let out = text;
    const inline = out.match(INLINE_OPTIONS_CLOSED);
    if (inline && inline.index !== undefined) {
      const before = heldOptions;
      takeOptions(inline[2]);
      // Only remove the line if we actually captured it — otherwise leave
      // the model's words alone rather than silently deleting content.
      if (heldOptions !== before) {
        out = out.slice(0, inline.index + inline[1].length) + out.slice(inline.index + inline[0].length);
      }
    }
    return sanitizeProse(out);
  };

  const push = (piece: string): string => {
    if (fenceBuffer !== null) {
      fenceBuffer += piece;
      const close = fenceBuffer.indexOf("```", fenceTag!.length);
      if (close === -1) return "";
      const inner = fenceBuffer.slice(fenceTag!.length, close);
      const after = fenceBuffer.slice(close + 3);
      if (fenceKind === "json") takePlan(inner);
      else takeOptions(inner);
      fenceBuffer = null;
      fenceTag = null;
      fenceKind = null;
      // Whatever the model wrote after the block is ordinary prose; the
      // block itself now comes out at flush, so it stays last either way.
      return push(after);
    }

    pending += piece;

    const at = pending.indexOf(BARE_FENCE);
    if (at !== -1) {
      const opened = classifyFence(pending.slice(at + BARE_FENCE.length));
      if (opened === "wait") {
        // Nothing from the backticks on may be streamed until the fence can
        // be told apart from a plain code block — emitting it early IS the
        // bug this guards against.
        const out = clean(pending.slice(0, at));
        pending = pending.slice(at);
        return out;
      }
      if (opened !== "prose") {
        const before = pending.slice(0, at);
        const rest = pending.slice(at + opened.tag.length);
        pending = "";
        fenceBuffer = opened.tag;
        fenceTag = opened.tag;
        fenceKind = opened.kind;
        // The fence may have opened AND closed inside this same piece.
        return clean(before) + push(rest);
      }
    }

    // No fence at all: the model wrote the object straight into its reply.
    const rawAt = unfencedPlanStart(pending);
    if (rawAt !== -1) {
      const out = clean(pending.slice(0, rawAt));
      const end = jsonObjectEnd(pending, rawAt);
      if (end === -1) {
        // Still arriving — hold it rather than type JSON into the bubble.
        pending = pending.slice(rawAt);
        return out;
      }
      takePlan(pending.slice(rawAt, end));
      const rest = pending.slice(end);
      pending = "";
      return out + push(rest);
    }

    const hold = holdLength(pending);
    const out = clean(pending.slice(0, pending.length - hold));
    pending = pending.slice(pending.length - hold);
    return out;
  };

  const flush = (): string => {
    if (fenceBuffer !== null) {
      // The stream ended with a fence still open (token limit, upstream cut,
      // watchdog abort). A partial block can't be grounded or rendered, and
      // the clients show an unterminated fence as raw text — drop it. If
      // nothing else was said the client sees an empty reply and shows its
      // "try again" state, which is honest.
      onDrop?.(`stream ended inside an open ${fenceTag} fence (${fenceBuffer.length} chars)`);
      fenceBuffer = null;
      fenceTag = null;
      fenceKind = null;
    }
    // Same for an unfenced object `push` was still holding: half an object
    // is not something any client can render, and it is what the bubble
    // would otherwise show.
    const unclosed = unfencedPlanStart(pending);
    if (unclosed !== -1 && jsonObjectEnd(pending, unclosed) === -1) {
      onDrop?.(`stream ended inside an unfenced plan object (${pending.length - unclosed} chars)`);
      pending = pending.slice(0, unclosed);
    }
    let out = clean(pending);
    pending = "";
    // Exactly one block, always last, so the clients' end-anchored fence
    // patterns match.
    const block = heldPlan
      ? `${JSON_FENCE}\n${heldPlan}\n\`\`\``
      : heldOptions
        ? `${OPTIONS_FENCE}\n${heldOptions}\n\`\`\``
        : "";
    if (heldPlan && heldOptions) onDrop?.("message carried both a plan and an options block — kept the plan");
    if (block) out = `${out.replace(/\s+$/, "")}\n\n${block}`;
    heldPlan = null;
    heldOptions = null;
    return out;
  };

  return { push, flush };
}
