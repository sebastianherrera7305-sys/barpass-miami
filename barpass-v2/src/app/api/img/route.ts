import sharp from "sharp";

/**
 * GET /api/img?u=<encoded image url>&w=<width>
 *
 * Resizes a venue photo before it ever reaches the phone.
 *
 * WHY THIS EXISTS
 * TestFlight, 2026-09-11, from inside a club: "tooo slow inside of the club,
 * too hard for people to even use it, like it's impossible". Measured: each
 * stored venue photo is ~262 KB, and a feed shows several at once — over 2 MB
 * of images for one screen. On the congested LTE inside a packed venue that is
 * the difference between a usable app and a dead one, and inside the venue is
 * exactly when the app has to work.
 *
 * The stored URLs are resolved googleusercontent links that IGNORE the usual
 * `=w400` sizing suffix (verified: HTTP 400). Re-fetching all 1,734 photos
 * from Google at a smaller width would work but costs a Places Details call
 * per venue. This does the same job for free and covers every venue at once,
 * including any added later.
 *
 * Cached hard at the edge: the upstream image is immutable for a given URL, so
 * a year-long public cache is safe and means each size is fetched from Google
 * once, ever.
 */

/** Only our own venue photos — this must never become an open image proxy. */
const ALLOWED_HOSTS = new Set([
  "lh3.googleusercontent.com",
  "places.googleapis.com",
  "maps.googleapis.com",
]);

/** Widths the app actually asks for. Anything else is clamped to the nearest,
 * so the cache can't be fragmented into thousands of one-off sizes. */
const ALLOWED_WIDTHS = [200, 400, 600, 900];

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const raw = searchParams.get("u");
  if (!raw) return new Response("missing u", { status: 400 });

  let upstream: URL;
  try {
    upstream = new URL(raw);
  } catch {
    return new Response("bad url", { status: 400 });
  }
  if (upstream.protocol !== "https:" || !ALLOWED_HOSTS.has(upstream.hostname)) {
    return new Response("host not allowed", { status: 403 });
  }

  const requested = Number(searchParams.get("w") ?? 400);
  const width = ALLOWED_WIDTHS.reduce((best, w) =>
    Math.abs(w - requested) < Math.abs(best - requested) ? w : best,
  );

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 15_000);
  let sourceBytes: ArrayBuffer;
  try {
    const res = await fetch(upstream.toString(), { signal: controller.signal });
    if (!res.ok) return new Response("upstream failed", { status: 502 });
    sourceBytes = await res.arrayBuffer();
  } catch {
    return new Response("upstream failed", { status: 502 });
  } finally {
    clearTimeout(timer);
  }

  try {
    const out = await sharp(Buffer.from(sourceBytes))
      .rotate() // honour EXIF orientation before resizing
      .resize({ width, withoutEnlargement: true })
      .jpeg({ quality: 72, progressive: true, mozjpeg: true })
      .toBuffer();

    return new Response(new Uint8Array(out), {
      headers: {
        "Content-Type": "image/jpeg",
        "Content-Length": String(out.byteLength),
        // Immutable per (url, width): the upstream photo never changes.
        "Cache-Control": "public, max-age=31536000, immutable",
        "CDN-Cache-Control": "public, max-age=31536000, immutable",
      },
    });
  } catch {
    return new Response("resize failed", { status: 500 });
  }
}
