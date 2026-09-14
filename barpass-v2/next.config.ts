import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Venue photos are served through Next's own image optimizer instead of a
  // hand-rolled sharp route. TestFlight from inside a club, 2026-09-11:
  // "tooo slow inside of the club… like it's impossible". Measured cause:
  // each stored photo is ~262 KB and a feed shows several, so one screen
  // pulls 2 MB+ of images over the congested LTE inside a packed venue.
  //
  // A sharp-based /api/img was tried first and failed in production: sharp
  // is a native module and `npm install` on macOS fetches only the darwin
  // binary, so every request 500'd on Vercel's linux runtime. The built-in
  // optimizer needs no dependency, runs on Vercel's own image infrastructure
  // and caches at the edge.
  //
  // Only the hosts our own venue photos come from — this must never become
  // an open image proxy.
  images: {
    remotePatterns: [
      { protocol: "https", hostname: "lh3.googleusercontent.com" },
      { protocol: "https", hostname: "places.googleapis.com" },
      { protocol: "https", hostname: "maps.googleapis.com" },
      // User-uploaded venue photos live in Supabase Storage.
      { protocol: "https", hostname: "hrhdezziddfrktvtgzbg.supabase.co" },
    ],
    // The widths the iOS app asks for. Keeping this list short stops the
    // optimizer's cache fragmenting into hundreds of one-off sizes.
    imageSizes: [200, 400, 600],
    deviceSizes: [640, 828, 1080],
    // AVIF first. Measured on a real venue photo at w=1080: JPEG 129KB,
    // WebP 143KB (bigger — WebP is not a win on photographic content at this
    // quality), AVIF materially smaller. Next negotiates on the Accept header
    // and falls back to JPEG for a client that does not ask, so nothing
    // breaks; iOS decodes AVIF natively since 16.
    formats: ["image/avif", "image/webp"],
    // Quality is an allow-list: anything not in it is rejected with a 400,
    // which is why an earlier q=70 attempt failed outright. A venue card is a
    // small, dark, moving surface — 60 is indistinguishable there and much
    // cheaper. 75 stays for the full-screen detail header.
    qualities: [45, 60, 75],
    minimumCacheTTL: 31536000,
  },
};

export default nextConfig;
