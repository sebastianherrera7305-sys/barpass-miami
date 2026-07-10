# BarPass — Project Intelligence

> Auto-loaded every session. Keep this file updated.

---

## What is BarPass

Miami nightlife access app. Skip the Line passes, VIP tables, event tickets, drink ordering. Universal design for all nationalities/demographics.

**Bundle ID:** `com.sebastian.barpass`
**GitHub:** `https://github.com/sebastianherrera7305-sys/barpass-miami`
**Web (GitHub Pages):** `https://sebastianherrera7305-sys.github.io/barpass-miami/barpass-miami.html`
**Firebase (legacy):** `barpass-app` · apiKey `AIzaSyB4uz5CaLCC3nsLz3QwOJtfp1bnBUqQUlg`
**Google Places API Key:** `AIzaSyDuvJwTrbSCOu69fECyYi2yBE9HXRdql9k` (local only, not on Vercel)
**Vercel Project:** `prj_c8dgoFRpNO3O6XrOICTdhPDPPuzm` (org `team_Jd4GkDOHmAEoirEFN3Jqc1W2`) — middleware.ts DELETED 2026-07-08 (was the 500-blocker; no auth-gated routes at launch). Build green: 181 venue pages SSG. Redeploy pending.

---

## Architecture

### iOS (Swift 6, iOS 17+)
```
Splash → Onboarding Video → Native Auth → MainTabView (native SwiftUI)
```

| Layer | Directory | Description |
|-------|-----------|-------------|
| **Domain Models** | `Models/` | `BarPassVenue`, `VenueType`, `CartItem`, `EventTicket`, `SkipLinePass`, `TableReservation` |
| **Repositories** | `Repositories/` | `VenueRepository` (protocol), `LocalVenueRepository` (actor), `RepositoryDependencies` (DI point) |
| **Stores** | `Models/` | `VenueStore` (@MainActor, @Published, receives repository via init) |
| **UI** | `Features/` | `MainTabView`, `TonightView`, `ExploreView`, `PlanView`, `ProfileView`, `CartView`, `CardPaymentView`, PriorityEntry screens |
| **Services** | `Core/Services/` | `HapticService`, `LocationService`, `NotificationService`, `BiometricService`, `ApplePayService`, `WalletPassService` |
| **Bridge** | `Core/Bridge/` | `NativeBridge.swift` — JS ↔ Swift communication for WebView |
| **Design System** | `Resources/DesignSystem.swift` | Colors, Radii, Spacing, Haptics, ShimmerSkeleton, glass modifier, `BarPassLogo` view |

**Important:** The `NativeBridge.swift` + WebView (`barpass-miami.html`) is the OLD architecture. NEW screens are built natively in SwiftUI (Tonight, Explore, Plan, Cart, etc.). The WebView is only used for legacy venue list/detail — **do not add new features to it**.

### Web V2 (Next.js App Router + TypeScript + Tailwind 4 + Supabase)
```
barpass-v2/
├── src/app/          — Pages (Discover, Concierge, Map, Venues/[slug], Profile, API routes)
├── src/features/     — Feature modules (venues, discover, ai, map, intelligence)
├── src/components/   — Shared UI (nav-bar, Badge, Button, Card)
├── src/lib/supabase/ — client.ts, server.ts, config.ts
├── supabase/schema.sql
└── scripts/enrich-venues.ts  — Google Places enrichment
```

---

## Session Status (Jul 6, 2026)

### ✅ COMPLETED — Repository Architecture Migration

Objective: Build a production-grade repository architecture for iOS that separates domain, data access, and UI state.

**What was done:**
1. `Resources/DesignSystem.swift` — Extracted all design tokens (Color, BPRadius, BPSpacing, BPHaptics, ShimmerSkeleton, glass modifier, BarPassLogo) from `Models/Venue.swift`
2. Renamed `Venue` → `BarPassVenue` (model) across all views + stores. `VenueType`, `VenueEvent`, `VenueStore`, `VenueRepository` keep their names
3. Added `BarPassVenue.preview` static for SwiftUI previews
4. Created `Repositories/VenueRepository.swift` — protocol with `getVenues`, `getVenue(id:)`, `getTrendingVenues`, `getOpenNowVenues`, `getHappyHourVenues`, `getVenuesByNeighborhood`, `searchVenues`
5. Created `Repositories/LocalVenueRepository.swift` — `actor` implementing `VenueRepository` with 6 hardcoded venues + `venue_media.json` merge at init
6. Created `Repositories/RepositoryDependencies.swift` — single DI point: `nonisolated(unsafe) static var venue: VenueRepository = LocalVenueRepository()`
7. Rewrote `VenueStore.swift` — no hardcoded data, repository injected via `init(repository:)`, async `loadVenues()` with `isLoading`/`loadError`
8. Updated `MainTabView.swift` — calls `venueStore.loadVenues()` on `.task`
9. Added BarPassLogo (`BARPASS` text logo, amber accent) to header of `TonightView`
10. Fixed all Swift 6 concurrency issues — actor init, nonisolated(unsafe), @MainActor haptics
11. Added all 4 new files (`DesignSystem.swift`, `VenueRepository.swift`, `LocalVenueRepository.swift`, `RepositoryDependencies.swift`) to Xcode project (`project.pbxproj`) — **BUILD SUCCEEDS**

### ✅ COMPLETED — Login Performance Optimization (Jul 6)

**Objective:** Reduce perceived login time to under 1 second.

**Root causes found:**
1. **WebView auth was orphaned** — `BarPassWebContainerView` never instantiated. Email/password and Apple Sign In were broken. Only "Continue as guest" worked.
2. **Splash had 7s animation chain** — 3.5s loading bar + 1.8s min timer + 7s safety timer
3. **Supabase fetches were serial** — events waited for venues (~500-2500ms)
4. **Post-login delays** — 0.5s auth fade + 0.6s action bar delay = 1.1s extra

**What was done:**
1. `Core/Services/AuthService.swift` — Native Supabase Auth via URLSession (`POST /auth/v1/token`). No WebView dependency. ~300-500ms vs 2-8s.
2. `AppState.swift` — Removed all splash timing gates (`minTimerDone`, `webReadyDone`). Entry is instant after auth.
3. `SplashView.swift` — Reduced from 7s chain to 0.3s spring + 0.6s auto-dismiss
4. `SupabaseVenueRepository.swift` — Parallelized venue + event fetches with `async let`
5. `TonightView.swift` — Added shimmer skeleton cards during loading; guarded empty sections
6. All animation durations reduced: auth fade 0.5→0.15s, action bar delay 0.6→0.15s, splash fade 0.4→0.15s

**Result:** Tap Sign In → Home visible in ~0.5-0.8s (down from 5-12s).

See `LOGIN_PERFORMANCE_REPORT.md` for full timing breakdown.

### ✅ COMPLETED — Supabase Backend + Admin Panel + Google Places Seed

**Status:** All done.

**What was built:**
1. **Supabase project created** (`hrhdezziddfrktvtgzbg`) with schema (`venues`, `events`, `profiles`, `favorites`, `night_plans` tables + RLS)
2. **`SupabaseVenueRepository.swift`** — actor that fetches venues from Supabase REST API via URLSession (no SPM needed). Falls back to `LocalVenueRepository` on network failure. Maps DB snake_case to `BarPassVenue` camelCase. Computes `isOpenNow`, `hasHappyHour`, `tags`, `crowdLevel`, `popularDrinks`, `priceRange`, etc.
3. **`RepositoryDependencies.swift`** — swapped to `SupabaseVenueRepository()`
4. **Admin CRUD in `barpass-v2/src/app/admin/`**:
   - `layout.tsx` — sidebar nav (Dashboard, Venues)
   - `page.tsx` — dashboard with venue count
   - `actions.ts` — server actions for INSERT/UPDATE/DELETE venues (uses service_role key)
   - `venues/page.tsx` — table list with search, edit, delete
   - `venues/new/page.tsx` — add venue form
   - `venues/[id]/page.tsx` — edit venue form
   - `venues/venue-form.tsx` — shared form with all schema fields
5. **176 venues seeded** via Google Places API across South Beach (48), Brickell (36), Wynwood (38), Downtown (9), Coconut Grove (26), Coral Gables (11), Design District (8). Plus 528 events (3 per venue).
6. **Keys in `.env.local`**: Supabase URL + anon + service_role, Google Places

### ❌ PENDING / KNOWN ISSUES

- **Vercel v2 deployment** — middleware.ts uses deprecated `supabaseMiddleware` pattern for Next.js 16. All routes return 500.
- **Stripe SPM** — `stripe-ios` package not added to Xcode project. `CardPaymentView` has UI only, no tokenization.
- **Apple Sign In capability** — not enabled in Xcode (code exists in `NativeAuthView.swift` + `AppleSignInHelpers.swift`).
- **OpenAI key** — missing. AI Concierge (`/api/concierge`) won't work.
- **Onboarding videos** — 6 Higgsfield clips not yet generated.
- **MapLibre** — works locally but not deployed.

---

## Design System — Deep Cosmos

Universal design for all audiences.

```swift
// Colors (in Color extension, DesignSystem.swift)
bpAmber        = Color(red: 0.92, green: 0.72, blue: 0.28)
bpAmberBright  = Color(red: 0.98, green: 0.86, blue: 0.50)
bpSurface      = Color(white: 0.06)
bpGreen        = Color(red: 0.2, green: 0.9, blue: 0.4)
bpDanger       = Color(red: 1, green: 0.42, blue: 0.42)
bpCardBackground = Color(red: 0.06, green: 0.04, blue: 0.10)

// Logo
BarPassLogo(subtitle: "MIAMI") → "BAR" (white) + "PASS" (amber) + amber underline
```

---

## Product Readiness Checklist

### 🔴 Crítico (blocker para cobrar)
- [ ] **Stripe SDK** — código listo en `CardPaymentView.swift`. Falta: (1) agregar SPM `stripe-ios` en Xcode, (2) poner publishable key real en `StripeConfig.swift`
- [ ] **Apple Pay** — merchant account verificado
- [ ] **Wallet top-up** — pago real
- [ ] **Apple Sign In** — habilitar capability en Xcode + configurar en Apple Developer portal
- [ ] **Supabase proyecto** — crear proyecto, correr schema, configurar keys
- [ ] **Privacy Policy + Terms of Service** — URLs públicas
- [ ] **Verificación de edad** — 21+

### 🟡 Importante (App Store)
- [ ] Apple Developer account activa ($99/año)
- [ ] Screenshots (6.7" y 6.1")
- [ ] **Datos reales de venues** — seed con Google Places + admin panel
- [ ] QR único por orden + validación en venue
- [ ] Sistema de órdenes en Supabase (no Firestore)

### 🟢 Post-lanzamiento
- [ ] Push notifications (FCM)
- [ ] Historial de órdenes
- [ ] Dashboard para venues
- [ ] Crashlytics + Analytics
- [ ] TestFlight

---

## Key Files

```
barpass/
├── CLAUDE.md                          ← este archivo
├── barpass-miami.html                 ← web app legacy (WebView)
├── barpass-map.html                   ← mapa legacy
├── admin.html                         ← admin legacy (Firebase)
├── barpass-v2/                        ← Next.js v2 app
│   ├── supabase/schema.sql            ← 5 tablas (venues, events, profiles, favorites, night_plans)
│   ├── scripts/enrich-venues.ts       ← Google Places seed
│   └── src/                           ← App Router pages, features, components
└── BarPass-iOS/BarPass/
    ├── Resources/DesignSystem.swift    ← Colores, radii, spacing, haptics, shimmer, glass, BarPassLogo
    ├── Models/
    │   ├── BarPassVenue.swift          ← Domain model (renamed from Venue)
    │   └── VenueStore.swift            ← @MainActor, repository injected
    ├── Repositories/
    │   ├── VenueRepository.swift       ← Protocol
    │   ├── LocalVenueRepository.swift  ← Actor, 6 venues hardcoded + venue_media.json
    │   └── RepositoryDependencies.swift← DI point
    ├── Features/
    │   ├── Main/MainTabView.swift      ← Tab bar + loadVenues()
    │   ├── Tonight/TonightView.swift   ← Header (BarPassLogo), venue cards
    │   ├── Auth/NativeAuthView.swift
    │   ├── Cart/                       ← CartView, CartStore, CardPaymentView
    │   └── PriorityEntry/              ← Hub, SkipLine, Table, Tickets, QR
    ├── Core/
    │   ├── Bridge/NativeBridge.swift   ← JS↔Swift
    │   └── WebView/BarPassWebView.swift
    └── app.xcodeproj                   ← Xcode project (Swift 6, iOS 17+)
```

---

## Standing Rules (IMPORTANT)

1. **V2 web = Next.js** — `barpass-v2/` (App Router + TS + Tailwind 4 + Supabase). New web features go there as `src/features/*` modules
2. **iOS = Swift nativo** — new iOS features in `BarPass-iOS/`, never in HTML
3. **HTML legacy** — `barpass-miami.html` etc. — bug fixes only, no new features
4. **Deep Cosmos** — black + amber (#ebb847), no culturally-specific colors
5. **iOS target** — iOS 17+, Swift 6
6. **Supabase = backend único** — web + iOS consume same tables (`barpass-v2/supabase/schema.sql`)
7. **Repository pattern** — iOS data access goes through `VenueRepository` protocol. Swap implementations in `RepositoryDependencies` (no view/store changes needed)
8. **Google Places** key is `AIzaSyDuvJwTrbSCOu69fECyYi2yBE9HXRdql9k` — local only, NOT on Vercel

---

## Connected Tools

- **Figma** — sebastianherrera7305@gmail.com (Starter)
- **Higgsfield** — connected, needs credits
- **GitHub** — sebastianherrera7305-sys/barpass-miami
- **Firebase (legacy)** — barpass-app
- **Vercel** — barpass-v2 (broken)
- **Supabase** — user needs to create project and share keys

---

*Última actualización: 2026-07-06*
