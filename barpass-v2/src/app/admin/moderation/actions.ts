"use server";

import type { SupabaseClient } from "@supabase/supabase-js";
import { requireModerator } from "./moderator";
import { VENUE_MEDIA_BUCKET, storagePathFromPublicUrl } from "./media-path";
import type { ActionResult, QueueItem, QueueResult, ReasonTally } from "./types";

/**
 * The server half of the review queue. Everything privileged happens here;
 * the page is a dumb renderer that holds no key and can reach no table.
 *
 * THE SCHEMA THIS EXPECTS (supabase/venue_media_moderation.sql, written by
 * the migration alongside this page — same shape as the chapter-chat
 * precedent in chapter_chat.sql):
 *   public.venue_media_reports(id, media_id → venue_media, reporter_id,
 *                              reason, created_at, resolved_at,
 *                              resolved_by, action)
 *     with unique(media_id, reporter_id)
 *   public.venue_media adds: hidden_at timestamptz, report_count int
 * If those are not in the database yet the page says so in words instead
 * of rendering an empty, reassuring-looking queue.
 */

/**
 * `reporter_id` is missing from this list ON PURPOSE and must stay missing.
 * The service-role client can read it; the moment it is selected it is one
 * careless spread away from the browser. A moderator who can see who
 * reported can retaliate — and then nobody reports anything again.
 */
const REPORT_COLUMNS = "media_id, reason, created_at";

/** Likewise: no `user_id`. The queue judges the photo, not the person. */
const MEDIA_COLUMNS = "id, venue_id, media_url, media_type, created_at, hidden_at, report_count";

/** A human can't triage more than this in a sitting; a bigger number is a paging problem, not a UI one. */
const MAX_REPORTS = 500;

type ReportRow = { media_id: string; reason: string | null; created_at: string };
type MediaRow = {
  id: string;
  venue_id: string;
  media_url: string;
  media_type: string;
  created_at: string;
  hidden_at: string | null;
  report_count: number | null;
};

/** PostgREST's way of saying "that table/column isn't there". */
function isMissingSchema(error: { code?: string; message?: string } | null): boolean {
  if (!error) return false;
  if (error.code === "42P01" || error.code === "42703" || error.code === "PGRST205") return true;
  return /does not exist|schema cache/i.test(error.message ?? "");
}

export async function loadQueue(accessToken: string | null): Promise<QueueResult> {
  const gate = await requireModerator(accessToken);
  if (!gate.ok) return { ok: false, error: gate.error };
  const { supabase } = gate;

  const { data: reportData, error: reportError } = await supabase
    .from("venue_media_reports")
    .select(REPORT_COLUMNS)
    .is("resolved_at", null)
    .order("created_at", { ascending: true })
    .limit(MAX_REPORTS);

  if (reportError) {
    return isMissingSchema(reportError)
      ? { ok: false, error: "schema_missing", detail: reportError.message }
      : { ok: false, error: "query_failed", detail: reportError.message };
  }

  const reports = (reportData ?? []) as ReportRow[];
  const loadedAt = new Date().toISOString();
  if (reports.length === 0) return { ok: true, items: [], loadedAt };

  const mediaIds = [...new Set(reports.map((r) => r.media_id))];
  const { data: mediaData, error: mediaError } = await supabase
    .from("venue_media")
    .select(MEDIA_COLUMNS)
    .in("id", mediaIds);

  if (mediaError) {
    return isMissingSchema(mediaError)
      ? { ok: false, error: "schema_missing", detail: mediaError.message }
      : { ok: false, error: "query_failed", detail: mediaError.message };
  }

  const media = (mediaData ?? []) as MediaRow[];
  const venueNames = await loadVenueNames(supabase, media.map((m) => m.venue_id));

  const items: QueueItem[] = media.map((m) => {
    const mine = reports.filter((r) => r.media_id === m.id);
    return {
      mediaId: m.id,
      venueId: m.venue_id,
      venueName: venueNames.get(m.venue_id) ?? m.venue_id,
      mediaUrl: m.media_url,
      mediaType: m.media_type === "video" ? "video" : "photo",
      postedAt: m.created_at,
      hiddenAt: m.hidden_at,
      // Count the unresolved reports we actually hold rather than trusting
      // the denormalised column: after a dismissal the two disagree, and
      // the queue should show what is still waiting on a decision.
      reportCount: mine.length,
      firstReportedAt: mine[0]?.created_at ?? m.created_at,
      reasons: tallyReasons(mine),
    };
  });

  // A report on media that is STILL LIVE is the urgent one — the photo is
  // public while it sits here. Something already auto-hidden is contained,
  // so it waits. Within each group: most-reported first, then oldest, so
  // nothing can be starved by a steady drip of fresher reports.
  items.sort((a, b) => {
    if (!a.hiddenAt !== !b.hiddenAt) return a.hiddenAt ? 1 : -1;
    if (a.reportCount !== b.reportCount) return b.reportCount - a.reportCount;
    return a.firstReportedAt.localeCompare(b.firstReportedAt);
  });

  return { ok: true, items, loadedAt };
}

async function loadVenueNames(
  supabase: SupabaseClient,
  venueIds: string[],
): Promise<Map<string, string>> {
  const names = new Map<string, string>();
  const unique = [...new Set(venueIds)];
  if (unique.length === 0) return names;
  // A missing venue name is cosmetic: the queue still works, so this never
  // fails the whole load.
  const { data } = await supabase.from("venues").select("id, name").in("id", unique);
  for (const row of (data ?? []) as { id: string; name: string | null }[]) {
    if (row.name) names.set(row.id, row.name);
  }
  return names;
}

function tallyReasons(reports: ReportRow[]): ReasonTally[] {
  const counts = new Map<string, number>();
  for (const r of reports) {
    const reason = (r.reason ?? "").trim() || "unspecified";
    counts.set(reason, (counts.get(reason) ?? 0) + 1);
  }
  return [...counts.entries()]
    .map(([reason, count]) => ({ reason, count }))
    .sort((a, b) => b.count - a.count || a.reason.localeCompare(b.reason));
}

/**
 * Remove: the row AND the file. Order is load-bearing — the bucket is
 * public, so a row deleted without its object leaves the photo on the
 * internet at a URL the reporter's harasser may already have.
 */
export async function removeMedia(
  accessToken: string | null,
  mediaId: string,
): Promise<ActionResult> {
  const gate = await requireModerator(accessToken);
  if (!gate.ok) return { ok: false, error: gate.error };
  const { supabase, user } = gate;

  const { data: row, error: readError } = await supabase
    .from("venue_media")
    .select("id, media_url")
    .eq("id", mediaId)
    .maybeSingle();
  if (readError) return { ok: false, error: "query_failed", detail: readError.message };
  if (!row) return { ok: true, warning: "That media was already gone." };

  // Best effort, and before the delete: if the FK is `on delete cascade`
  // these rows vanish with the media anyway, but if it isn't, this is the
  // only trace left of why a photo disappeared.
  await supabase
    .from("venue_media_reports")
    .update({ resolved_at: new Date().toISOString(), resolved_by: user.id, action: "media_removed" })
    .eq("media_id", mediaId)
    .is("resolved_at", null);

  let warning: string | undefined;
  const path = storagePathFromPublicUrl((row as { media_url: string }).media_url);
  if (!path) {
    warning = "The row is gone, but the file isn't in the venue-media bucket — delete it by hand.";
  } else {
    const { error: storageError } = await supabase.storage.from(VENUE_MEDIA_BUCKET).remove([path]);
    if (storageError) {
      // Do NOT stop here. Leaving the row would keep the photo in the app,
      // which is worse than an orphaned file — but say so out loud.
      warning = `The file may still be in storage (${path}): ${storageError.message}`;
    }
  }

  const { error: deleteError } = await supabase.from("venue_media").delete().eq("id", mediaId);
  if (deleteError) {
    // 23503: the reports still point at it and the FK doesn't cascade.
    if (deleteError.code === "23503") {
      await supabase.from("venue_media_reports").delete().eq("media_id", mediaId);
      const retry = await supabase.from("venue_media").delete().eq("id", mediaId);
      if (retry.error) return { ok: false, error: "query_failed", detail: retry.error.message };
      return { ok: true, warning };
    }
    return { ok: false, error: "query_failed", detail: deleteError.message };
  }

  return { ok: true, warning };
}

/**
 * Dismiss: the photo comes back. Un-hide FIRST — if the second write fails
 * the item stays in the queue and can be retried, whereas the reverse order
 * would drop it from the queue while leaving it hidden from the app, which
 * is a silent takedown nobody would ever notice.
 */
export async function dismissReports(
  accessToken: string | null,
  mediaId: string,
): Promise<ActionResult> {
  const gate = await requireModerator(accessToken);
  if (!gate.ok) return { ok: false, error: gate.error };
  const { supabase, user } = gate;

  const { error: unhideError } = await supabase
    .from("venue_media")
    .update({ hidden_at: null, report_count: 0 })
    .eq("id", mediaId);
  if (unhideError) {
    return isMissingSchema(unhideError)
      ? { ok: false, error: "schema_missing", detail: unhideError.message }
      : { ok: false, error: "query_failed", detail: unhideError.message };
  }

  const { error: resolveError } = await supabase
    .from("venue_media_reports")
    .update({ resolved_at: new Date().toISOString(), resolved_by: user.id, action: "dismissed" })
    .eq("media_id", mediaId)
    .is("resolved_at", null);
  if (resolveError) return { ok: false, error: "query_failed", detail: resolveError.message };

  return { ok: true };
}
