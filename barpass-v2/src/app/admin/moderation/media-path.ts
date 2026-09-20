/**
 * Turning a stored `venue_media.media_url` back into the object path inside
 * the Storage bucket.
 *
 * WHY THIS EXISTS: `venue-media` is a PUBLIC bucket (venue_media.sql). So
 * deleting the row only removes the photo from the app — the file is still
 * fetchable forever by anyone who kept the URL, which on this feature means
 * anyone who saw the story. "Remove" has to mean both, and removing the
 * file needs the path, which only the URL still carries once the row is
 * gone. Hence: derive the path FIRST, delete the file, then delete the row.
 */

export const VENUE_MEDIA_BUCKET = "venue-media";

const PUBLIC_MARKER = `/object/public/${VENUE_MEDIA_BUCKET}/`;
const SIGNED_MARKER = `/object/sign/${VENUE_MEDIA_BUCKET}/`;
const AUTH_MARKER = `/object/authenticated/${VENUE_MEDIA_BUCKET}/`;

/**
 * The key to pass to `storage.from('venue-media').remove([...])`, or null
 * when this URL is not a venue-media object (an externally hosted image, a
 * hand-edited row, a different bucket). Null is not a failure to swallow:
 * the caller must tell the moderator the file could not be identified
 * rather than report a clean delete.
 */
export function storagePathFromPublicUrl(mediaUrl: string): string | null {
  // Parsed only to reject non-URLs and non-web schemes. The PATH is taken
  // from the raw string below, because `new URL()` silently resolves ".."
  // away: ".../venue-media/me/../you/x.jpg" normalises to
  // ".../venue-media/you/x.jpg", and the traversal check further down
  // would then have nothing left to catch — the delete would already be
  // aimed at someone else's folder.
  let parsed: URL;
  try {
    parsed = new URL(mediaUrl);
  } catch {
    return null;
  }
  if (parsed.protocol !== "https:" && parsed.protocol !== "http:") return null;

  const pathname = mediaUrl.split("#")[0].split("?")[0];

  const marker = [PUBLIC_MARKER, SIGNED_MARKER, AUTH_MARKER].find((m) => pathname.includes(m));
  if (!marker) return null;

  const raw = pathname.slice(pathname.indexOf(marker) + marker.length);
  if (!raw) return null;

  // Storage stores the decoded key; the URL carries it percent-encoded
  // (uploads from iOS can contain spaces). Decode per segment so an
  // encoded "/" inside a filename can't silently become a directory.
  let path: string;
  try {
    path = raw.split("/").map(decodeURIComponent).join("/");
  } catch {
    return null;
  }

  // The path comes from our own database, but it is still user-influenced
  // (the uploader picks the filename). A traversal segment here would aim
  // the delete at another user's folder.
  if (path.split("/").some((seg) => seg === "." || seg === ".." || seg === "")) return null;

  return path;
}
