# BarPass V2 — Launch Audit

**Date:** 2026-07-05 · **Target launch:** 2026-08-15 · **Scope:** `barpass-v2/` (Next.js web)
**Method:** Ran the app, hit every route, read the middleware/map/concierge/venue code, checked build + types + lint.

Severity legend — **Critical** = blocks launch / app broken · **High** = launch-quality gap users will notice · **Medium** = polish & debt · **Low** = nice-to-have.
Complexity — **S** ≤ half day · **M** ~1–2 days · **L** ~3–5 days.

---

## Critical

### C1 — Entire site returned HTTP 500 on every route ✅ FIXED (this session)
- **Root cause:** `src/middleware.ts` runs on every request and called `createServerClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, …)`. There is no `.env.local`, so both env vars were `undefined` and `@supabase/ssr` throws *"Your project's URL and Key are required"* before any page renders. `next build` passed because middleware only executes at request time — the outage was invisible to the build. The redirect guard was also dead logic (`!pathname.startsWith("/")` is always false).
- **Fix applied:** Added `src/lib/supabase/config.ts` (`getSupabaseEnv()` / `isSupabaseConfigured()`). Middleware now no-ops safely when Supabase is unconfigured and only refreshes the session (no route gating) when it is. Verified: all routes now 200, `tsc` + eslint clean.
- **Complexity:** S · **Files:** `src/middleware.ts`, `src/lib/supabase/config.ts`

### C2 — The map is a black void with floating icons (Priority #2)
- **Root cause:** No map library is installed (`mapbox-gl` was removed; nothing replaced it). `venue-map.tsx` renders venues as absolutely-positioned icons over a hand-computed Miami lat/lng bounding box. There are no tiles, streets, water, or neighborhoods — users cannot tell *where* anything is or how venues relate spatially. This is the single biggest quality gap.
- **Best solution:** Adopt **MapLibre GL JS** with a **free CARTO dark-matter vector style** (`https://basemaps.cartocdn.com/gl/dark-matter-gl-style/style.json`). No access token, no account gate, ships today, and matches the Deep Cosmos aesthetic. Real pan/zoom at 60fps, GeoJSON source + native clustering, custom amber HTML markers, `flyTo` on select, geolocate control. Keep the existing filter/search/list UI (it's good) and swap only the render surface. Architecture stays swap-friendly: a `<BaseMap>` wrapper isolates the library so Mapbox can replace it later by changing one file.
- **Why better than Mapbox:** Mapbox requires an account + `NEXT_PUBLIC_MAPBOX_TOKEN` (a launch blocker on someone else's action) and bills per load. MapLibre + CARTO is genuinely free and open, with the same GL feature set.
- **Complexity:** M · **Files:** new `src/features/map/components/base-map.tsx`, `venue-marker.tsx`, `use-map-venues.ts`; refactor `venue-map.tsx`; add `maplibre-gl` dep.

---

## High

### H1 — AI Concierge ("the soul") is non-functional without a key
- **Root cause:** No `OPENAI_API_KEY` in env → `/api/concierge` correctly returns `ai_not_configured`, so "Remy" never produces a plan. The code path is sound; the capability is dark.
- **Best solution:** **User action required** — add `OPENAI_API_KEY` to `.env.local` (and Vercel env). Recommend also adding a tiny curated **fallback plan generator** so a demo/investor never hits a dead concierge if the key is missing or the API rate-limits. Founder call: the AI is the headline feature — it must degrade to *something* delightful, never to an error card.
- **Complexity:** S (key) + S (fallback) · **Files:** `.env.local` (user), optional `src/features/ai/services/fallback-planner.ts`

### H2 — No "Getting There" / Uber on venue pages (Priority #4)
- **Root cause:** Not built. Venue detail has no transport actions.
- **Best solution:** A `getDirectionsLinks(venue)` service returning provider deep links — Uber (`https://m.uber.com/ul/?action=setPickup&dropoff[latitude]=…&dropoff[longitude]=…&dropoff[nickname]=…`), Apple Maps, Google Maps — rendered as a "Getting There" section. One service = trivial to add providers later. Uber's universal link opens the app if installed, else mobile web/App Store, no extra taps.
- **Complexity:** S–M · **Files:** new `src/features/venues/services/directions.ts`, `getting-there.tsx`; edit `venues/[slug]/page.tsx`

### H3 — Latent perf regression once Supabase is configured
- **Root cause:** Middleware calls `auth.getUser()` on every matched request. When Supabase *is* configured, that's a network round-trip added to every navigation (the "feels slow" risk returns).
- **Best solution:** Only touch the session when a Supabase auth cookie is actually present (skip the call for anonymous visitors, which is everyone pre-login). Revisit when auth ships.
- **Complexity:** S · **Files:** `src/middleware.ts`

---

## Medium

### M1 — File-size rule violations (300-line max)
- `src/app/venues/[slug]/page.tsx` — **313 lines**. Extract `VenueHero`, `VenueEventsSection`, `VenueReviews`, `NearbyVenues` into `features/venues/components/`.
- `src/features/map/components/venue-map.tsx` — **283 lines**, will exceed once real map lands → split per C2.
- `src/features/venues/data/venues.ts` — 333 lines but it's static seed data, acceptable until it moves to Supabase.
- **Complexity:** S · **Files:** as above.

### M2 — Production performance not yet measured
- **Root cause:** All timings so far are Next dev mode (compiles per route, inflated). Real launch numbers require `next build && next start` + Lighthouse.
- **Best solution:** Run a production build, capture LCP/TTFB per route and JS bundle size; set budgets. Home & venue pages should be static (they already use local data → SSG-friendly).
- **Complexity:** S

### M3 — Placeholder UI presented as real
- Map "current location" button is a UI placeholder (no geolocation). Profile page is static. Photos on venue pages are emoji grids. Acceptable for launch **only if** clearly framed; otherwise wire geolocation (comes free with C2's MapLibre geolocate control) and mark Profile sections honestly.
- **Complexity:** S–M

---

## Low
- **L1** — No favorites/save persistence (Save buttons exist visually). Needs Supabase or localStorage. Defer until auth.
- **L2** — No real reviews backend; review bars are static. Fine for launch as "atmosphere" summary if labeled.
- **L3** — Events use hardcoded July 2026 dates; will go stale. Move to data source with relative logic when Supabase lands.

---

## What's actually good (keep)
- Clean feature-first architecture (`features/{ai,map,venues,discover}` with components/hooks/services/types).
- Venue read layer is properly isolated (`venue-service.ts`) — Supabase swap = one file.
- Concierge API is server-only, Zod-validated, typed end-to-end.
- Design system (Deep Cosmos) is consistent; nav works on mobile + desktop; no dead nav links.
- Discover page structure (trending / happy-hour / neighborhood rows) is the right "what should I do tonight?" shape.

---

## Recommended sequence
1. ~~C1 site outage~~ ✅ done
2. **C2 real map** (biggest visible win, unblocks geolocation for M3)
3. **H2 Uber/Getting-There** (small, high-delight, Priority #4)
4. **H1 concierge key + fallback** (needs your OpenAI key)
5. M1 file splits → H3 middleware perf → M2 prod perf pass
