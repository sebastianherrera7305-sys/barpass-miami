"use client";

import { useState } from "react";
import type { ActionResult, QueueItem } from "./types";

/**
 * One reported photo or video, and the only two decisions there are.
 *
 * Both are hard to undo — remove destroys the file, dismiss puts the media
 * back in front of everyone — so neither fires on a single click. The
 * confirmation is inline rather than window.confirm(): a native dialog
 * hides the photo you are deciding about behind the browser chrome, which
 * is exactly the moment you want to still be looking at it.
 */

type Pending = "remove" | "dismiss" | null;

export function QueueItemCard({
  item,
  blurred,
  onRemove,
  onDismiss,
}: {
  item: QueueItem;
  blurred: boolean;
  onRemove: () => Promise<ActionResult>;
  onDismiss: () => Promise<ActionResult>;
}) {
  const [pending, setPending] = useState<Pending>(null);
  const [busy, setBusy] = useState(false);
  const [revealed, setRevealed] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const hide = blurred && !revealed;

  async function run(action: () => Promise<ActionResult>) {
    setBusy(true);
    setError(null);
    const result = await action();
    setBusy(false);
    setPending(null);
    if (!result.ok) setError(result.detail ?? "That didn't go through. Try again.");
  }

  return (
    <article className="rounded-xl border border-white/10 bg-white/5 p-4">
      <div className="flex flex-col gap-4 sm:flex-row">
        <div className="relative shrink-0 overflow-hidden rounded-lg bg-black/40 sm:w-48">
          {item.mediaType === "video" ? (
            <video
              src={item.mediaUrl}
              controls
              preload="metadata"
              className={`h-56 w-full object-cover sm:h-48 ${hide ? "blur-2xl" : ""}`}
            />
          ) : (
            /* Not next/image: these are arbitrary user uploads on a public
               bucket, and routing them through the optimizer would cache a
               copy of content we may be about to delete. */
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={item.mediaUrl}
              alt={`Reported ${item.mediaType} posted at ${item.venueName}`}
              className={`h-56 w-full object-cover sm:h-48 ${hide ? "blur-2xl" : ""}`}
            />
          )}
          {hide && (
            <button
              onClick={() => setRevealed(true)}
              className="absolute inset-0 grid place-items-center bg-black/30 text-xs font-bold text-white"
            >
              Tap to reveal
            </button>
          )}
        </div>

        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <h3 className="truncate font-bold text-white">{item.venueName}</h3>
            {item.hiddenAt ? (
              <span className="rounded-full bg-amber-400/15 px-2 py-0.5 text-[11px] font-bold text-amber-300">
                Auto-hidden
              </span>
            ) : (
              <span className="rounded-full bg-red-500/15 px-2 py-0.5 text-[11px] font-bold text-red-300">
                Still live
              </span>
            )}
          </div>

          <p className="mt-1 text-sm text-white/60">
            {item.reportCount} {item.reportCount === 1 ? "report" : "reports"} · first{" "}
            {timeAgo(item.firstReportedAt)} · posted {timeAgo(item.postedAt)}
          </p>

          <ul className="mt-2 flex flex-wrap gap-1.5">
            {item.reasons.map((r) => (
              <li
                key={r.reason}
                className="rounded-md border border-white/10 bg-black/30 px-2 py-1 text-xs text-white/70"
              >
                {labelReason(r.reason)}
                {r.count > 1 ? ` ×${r.count}` : ""}
              </li>
            ))}
          </ul>

          {error && <p className="mt-3 text-sm text-red-400">{error}</p>}

          <div className="mt-4">
            {pending === null && (
              <div className="flex flex-wrap gap-2">
                <button
                  onClick={() => setPending("remove")}
                  className="rounded-lg bg-red-500/90 px-3 py-2 text-sm font-bold text-white hover:bg-red-500"
                >
                  Remove
                </button>
                <button
                  onClick={() => setPending("dismiss")}
                  className="rounded-lg border border-white/15 px-3 py-2 text-sm font-bold text-white/80 hover:border-white/30"
                >
                  Dismiss
                </button>
              </div>
            )}

            {pending === "remove" && (
              <Confirm
                question="Delete the file and the row. There is no undo, and the person who posted it isn't told why."
                confirmLabel={busy ? "Removing…" : "Yes, remove it"}
                tone="danger"
                busy={busy}
                onCancel={() => setPending(null)}
                onConfirm={() => run(onRemove)}
              />
            )}

            {pending === "dismiss" && (
              <Confirm
                question="This puts the media back in the app for everyone and clears the reports."
                confirmLabel={busy ? "Restoring…" : "Yes, it's fine"}
                tone="neutral"
                busy={busy}
                onCancel={() => setPending(null)}
                onConfirm={() => run(onDismiss)}
              />
            )}
          </div>
        </div>
      </div>
    </article>
  );
}

function Confirm({
  question,
  confirmLabel,
  tone,
  busy,
  onCancel,
  onConfirm,
}: {
  question: string;
  confirmLabel: string;
  tone: "danger" | "neutral";
  busy: boolean;
  onCancel: () => void;
  onConfirm: () => void;
}) {
  return (
    <div className="rounded-lg border border-white/10 bg-black/40 p-3">
      <p className="text-sm text-white/70">{question}</p>
      <div className="mt-3 flex flex-wrap gap-2">
        <button
          onClick={onConfirm}
          disabled={busy}
          className={`rounded-lg px-3 py-2 text-sm font-bold disabled:opacity-40 ${
            tone === "danger" ? "bg-red-500 text-white" : "bg-amber-400 text-black"
          }`}
        >
          {confirmLabel}
        </button>
        <button
          onClick={onCancel}
          disabled={busy}
          className="rounded-lg px-3 py-2 text-sm text-white/50 hover:text-white disabled:opacity-40"
        >
          Cancel
        </button>
      </div>
    </div>
  );
}

/** The report vocabulary the RPC accepts, rendered for a human. Anything
 *  unknown is shown as-is rather than swallowed — a reason we don't
 *  recognise is still information. */
const REASON_LABELS: Record<string, string> = {
  nudity: "Nudity or sexual content",
  violence: "Violence",
  harassment: "Harassment or bullying",
  hate: "Hate speech",
  me: "I'm in this photo",
  minor: "Someone under 21",
  illegal: "Illegal activity",
  spam: "Spam",
  other: "Other",
  unspecified: "No reason given",
};

function labelReason(reason: string): string {
  return REASON_LABELS[reason] ?? reason;
}

function timeAgo(iso: string): string {
  const then = new Date(iso).getTime();
  if (Number.isNaN(then)) return "at an unknown time";
  const minutes = Math.round((Date.now() - then) / 60000);
  if (minutes < 1) return "just now";
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.round(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  return `${Math.round(hours / 24)}d ago`;
}
