/**
 * The only shapes that cross the server → client boundary of the review
 * queue.
 *
 * WHY THIS FILE IS SHORT ON PURPOSE
 * The server reads `venue_media_reports` with the service-role key, which
 * can see `reporter_id`. Nothing below has a field to put it in, and the
 * SELECT in actions.ts never names the column — so the moderator's browser
 * is not "trusted to hide it", it is never sent it. Reporting is only safe
 * while the person reporting stays invisible to the person deciding: a
 * moderator who can see who reported can retaliate, or be pressured into
 * telling someone who will. That is the whole point of the feature.
 *
 * The same rule applies in the other direction, which is easy to miss:
 * `venue_stories.sql` revokes `venue_media.user_id` from every client role,
 * so a queue that showed "posted by …" would be re-opening the leak the
 * stories work closed. The queue shows the PHOTO, not the person.
 */

/** A photo/video waiting on a human decision. */
export interface QueueItem {
  mediaId: string;
  venueId: string;
  /** Falls back to the raw id when a venue row is missing — never blank. */
  venueName: string;
  mediaUrl: string;
  mediaType: "photo" | "video";
  /** When the media was posted (ISO). */
  postedAt: string;
  /** Non-null once the report threshold auto-hid it from the app. */
  hiddenAt: string | null;
  /** Unresolved reports on this media. */
  reportCount: number;
  /** Oldest unresolved report (ISO) — how long someone has been waiting. */
  firstReportedAt: string;
  /** Reasons given, most-cited first. No timestamps per reason: a precise
   *  report time plus a venue is itself a way to guess who reported. */
  reasons: ReasonTally[];
}

export interface ReasonTally {
  reason: string;
  count: number;
}

export type QueueResult =
  | { ok: true; items: QueueItem[]; loadedAt: string }
  | { ok: false; error: ModerationError; detail?: string };

export type ActionResult =
  | { ok: true; warning?: string }
  | { ok: false; error: ModerationError; detail?: string };

/**
 * Deliberately coarse. `not_a_moderator` covers both "your email is not on
 * the list" and "your email is not confirmed" — telling a stranger which
 * one it was turns this page into an oracle for valid staff addresses.
 */
export type ModerationError =
  | "not_authenticated"
  | "not_a_moderator"
  | "moderation_not_configured"
  | "backend_not_configured"
  | "schema_missing"
  | "query_failed";

export const ERROR_COPY: Record<ModerationError, string> = {
  not_authenticated: "Sign in to continue.",
  not_a_moderator: "This account can't review reports.",
  moderation_not_configured:
    "No moderators are configured on this deployment, so nobody can open this page. Set BARPASS_MODERATOR_EMAILS and redeploy.",
  backend_not_configured: "Supabase isn't configured on this deployment.",
  schema_missing:
    "The reports table isn't in the database yet — apply supabase/venue_media_moderation.sql first.",
  query_failed: "Couldn't read the queue. Try again.",
};
