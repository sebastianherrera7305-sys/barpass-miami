# BarPass — Project Intelligence

> Auto-loaded every session. Keep this file updated.

---

## What is BarPass

Miami nightlife access app. Skip the Line passes, VIP tables, event tickets, drink ordering. Universal design for all nationalities/demographics.

**Bundle ID:** `com.sebastian.barpass`
**GitHub:** `https://github.com/sebastianherrera7305-sys/barpass-miami`
**Web (GitHub Pages):** `https://sebastianherrera7305-sys.github.io/barpass-miami/barpass-miami.html`
**Firebase (legacy):** `barpass-app` · apiKey `AIzaSy<REDACTED>`
**Google Places API Key:** `AIzaSy<REDACTED>` (local only, not on Vercel)
**Vercel Project:** `<VERCEL_PROJECT_ID>` (org `<VERCEL_ORG_ID>`) — **LIVE at `https://barpass-v2.vercel.app`** (deployed 2026-07-14). Env vars set on Vercel: NEXT_PUBLIC_SUPABASE_URL, NEXT_PUBLIC_SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY, VENUE_VALIDATION_SECRET. Still missing on Vercel: STRIPE_SECRET_KEY, NVIDIA_API_KEY (add when available — `/api/concierge` uses NVIDIA NIM/Llama 3.3, not OpenAI; not set locally either, so the endpoint 503s `ai_not_configured` everywhere today). iOS `APIClient.baseURL` points here now (old `barpass-miami.vercel.app` Express/Firestore backend was never deployed and is dead).
**Stripe SPM:** `stripe-ios@23.32.0` resolved in pbxproj, `CardPaymentView` does real client-side tokenization + calls `/api/transactions` (real Stripe PaymentIntent server-side).
**Stripe account:** `acct_1TmM3pHzVF9FsUCt` (US). **Test mode is wired and verified end-to-end** (2026-08-31): `STRIPE_SECRET_KEY` (`sk_test_…`) is in `barpass-v2/.env.local`, and a real test PaymentIntent of $25 came back `succeeded`. `StripeConfig.publishableKey` was pointing at a *different* account (`acct_…TmM4d`) and was corrected — a mismatch silently breaks charges (client tokenizes on one account, server charges on another), so **always verify the `pk_`/`sk_` account prefixes match**. `charges_enabled`/`payouts_enabled` are `false` because the account isn't activated yet — blocked on the company incorporation papers, not on code. Test mode needs no business verification, so all development/TestFlight work can proceed now; going live is a key swap in three places (`.env.local`, Vercel, `StripeConfig.swift`), no code changes.
**Payments — why Stripe and not Apple:** Apple Pay is only a wallet, not a processor; it still needs Stripe behind it to settle. And Apple's own guideline 3.1.3(e) *forbids* IAP for goods/services consumed outside the app (skip-the-line passes, tables, tickets, drinks all qualify), so IAP isn't an alternative — it's a rejection. Don't revisit this.
**Apple Developer Program:** ACTIVE (paid, 2026-07-14). Team ID `<APPLE_TEAM_ID>`. Entitlements (`BarPass.entitlements`) now wired into the build via `CODE_SIGN_ENTITLEMENTS`. Sign In with Apple code complete (`NativeAuthView` + `AuthService.signInWithApple`). **Capabilities confirmed live in Xcode → Signing & Capabilities (2026-08-27):** Sign In with Apple, Apple Pay (merchant ID `merchant.com.barpass.app` registered and checked), App Groups, Face ID, Location (When In Use), Media Library, Photo Library (+ Add Only), Push Notifications — all already enabled, nothing pending here. MusicKit itself isn't an Xcode capability; it's the Media ID `media.barpass` under Certificates, Identifiers & Profiles → Identifiers → Media IDs (also already created).

---

## Architecture

### iOS (Swift 6, iOS 17+) — FULL NATIVE
```
Splash → Onboarding Video → Native Auth → MainTabView (5 tabs)
```

| Layer | Directory | Description |
|-------|-----------|-------------|
| **Domain Models** | `Models/` | `BarPassVenue`, `VenueType`, `Trip`, `NightPlan`, `CartItem`, `EventTicket`, `SkipLinePass`, `TableReservation` |
| **Repositories** | `Repositories/` | `VenueRepository`, `TripRepository`, `PlanRepository` (protocols). `SupabaseVenueRepository` (actor), `LocalVenueRepository`, `LocalPlanRepository` (disk fallback, not the default), `SupabasePlanRepository` (**live, wired as the real dependency** — `RepositoryDependencies.plan`, real shared backend against `public.night_plans`, jsonb blob, RLS scoped to `auth.uid()`), `SupabaseTripRepository` (**live, wired as the real dependency** — real shared backend against `trips_schema.sql`, not a placeholder). `LocalTripRepository` deleted 2026-08-27 (dead code, orphaned since the Supabase migration) |
| **DI** | `Repositories/RepositoryDependencies.swift` | `nonisolated(unsafe) static var venue/trip/plan` — swap implementations one line |
| **Stores** | `Models/VenueStore.swift`, `Models/TripStore.swift` | `@MainActor`, `@Published`, repository injected via init |
| **UI** | `Features/` | `MainTabView` (5 tabs), `TonightView`, `ExploreView`, `TripsListView`, `PlanView`, `ProfileView`, `CartView`, `CardPaymentView`, PriorityEntry hub, Trip detail/creation flow |
| **Services** | `Core/Services/` | `AuthService`, `HapticService`, `LocationService`, `NotificationService`, `ApplePayService`, `ImageCache` |
| **Design System** | `Resources/DesignSystem.swift` | Colors, radii, spacing, haptics, shimmer, glass, `BarPassLogo`, font helpers, entrance animation |
| **Cache** | `Core/Services/ImageCache.swift` | `NSCache` hot/standard tiers, `CachedImage` view with ImageIO downsampling |
| **Auth** | `Core/Services/AuthService.swift` | Native Supabase Auth via URLSession (no WebView, no SDK). `restoreSession()` sync from UserDefaults. `signIn`, `signUp`, `sendPasswordReset`, `signOut` |
| **Privacy** | `Resources/PrivacyInfo.xcprivacy` | iOS 17+ privacy manifest |
| **Web (legacy)** | `Web/` | Only `barpass-logo.svg` remains. Old Bridge/WebView removed. |

### Web V2 (Next.js App Router + TypeScript + Tailwind 4 + Supabase)
```
barpass-v2/
├── src/app/          — Pages (Discover, Concierge, Map, Venues/[slug], Profile, API routes, Admin CRUD)
├── src/features/     — Feature modules (venues, discover, ai, map, intelligence)
├── src/components/   — Shared UI (nav-bar, Badge, Button, Card)
├── src/lib/supabase/ — client.ts, server.ts, config.ts, service.ts, require-user.ts
├── supabase/schema.sql
└── scripts/enrich-venues.ts  — Google Places enrichment
```

### TestFlight uploads — two traps that cost time on 2026-09-01
- **`/v1/apps/{id}/builds` returns NO guaranteed order.** Querying it with a
  small `limit` returns an arbitrary subset, so a freshly uploaded build can
  look missing when it is already `VALID`. Always fetch `limit=50` and sort by
  version client-side. Believing the short query led to two pointless
  re-uploads.
- **Xcode auto-increments the build number on upload when it is already
  taken.** Those two re-uploads therefore landed as builds 18 and 19, and the
  pbxproj said 18 while TestFlight's newest was 19 — the next archive would
  have collided again. After any upload, check what Apple actually holds and
  align `CURRENT_PROJECT_VERSION`.
- A `Progress 43%: Upload succeeded` line is not a truncated upload; it is
  just the percentage at that instant.

### Venue data — what is real and what is not (2026-09-01 audit)
The catalogue is 1846 rows; **1814 are served**, 32 are excluded. Two columns
answer two different questions and BOTH must be filtered on every read:
`business_status` (Google: does this still exist) and `excluded_reason`
(does this belong in a nightlife app — airport lounges, a cruise-ship lounge,
a cinema, smoke shops, promoters/concierges that resell entry to other
clubs, a pub-crawl tour operator, a yacht charter, a directory record for a
business that does not exist, closed/demolished venues, one exact duplicate).
Filter as `or=(business_status.is.null,business_status.neq.CLOSED_PERMANENTLY)`
— a bare `not.eq` is NULL, not true, for the 171 venues Google never reached
and silently drops them.

**`music_genres` was fabricated.** Until 2026-09-01 all 175 rows carrying it
were Miami and every one held the identical `['hip_hop','house']` — including
sports bars and a brewery. The likely origin is a promoter listing whose ad
copy reads "HIP HOP, HOUSE, EDM, LATIN" describing *other people's* clubs.
All 182 Miami venues have since been researched one at a time against primary
sources; 0 fabricated tags remain. Of 62 in the final pass, only 2 genuinely
warranted `hip_hop, house`.

**Rules that came out of it, and are worth keeping:**
- Never write a genre/field that no source states. An empty value is a fact
  (McSorley's NYC and Hopleaf Chicago have no music *by design*); a guessed
  one is a lie that survives for months because nothing marks it as guessed.
- **Update by id, never by name.** Names repeat across (and within) cities —
  updating `name=eq.…` wrongly excluded three legitimate Miller's Ale House
  rows and the real Bloomington Kilroy's before it was caught.
- Absence must never render as a value: `avg_spend = 0` was showing as a
  confident "$0" on 1665 venues (iOS already returned "N/A"; the web did not).
- `neighborhood` was wrong on more than half the researched venues (Coconut
  Grove alone held eight venues that were not in it). 41 are fixed from
  verified addresses. Geometry *detects* these but cannot *correct* them —
  the catalogue has no label to move them to.

**Genre vocabulary** is 14 cases; `country`, `rock`, `blues`, `afrobeats` were
added because the original ten were Miami-only and everything else collapsed
into `live` (8 of 9 researched Nashville venues are country). `live` is a
performance FORMAT, not a genre, and composes: a honky-tonk is `[country, live]`.
Still missing and seen repeatedly: reggae/calypso, soca, vallenato, merengue,
bachata.

### Shared helpers (dedupe refactors, 2026-08-31)
- **iOS — `Repositories/SupabaseRESTClient.swift`**: the one place that knows the Supabase REST base URL, anon key, auth headers, and the snake_case/iso8601 coders. All 12 repositories build requests through `SupabaseRESTClient.request(...)` + `.send(...)` instead of repeating the boilerplate. Two deliberate exceptions keep their own coders/raw calls: `SupabasePlanRepository` (its `plan` jsonb blob must not be re-cased) and the repos that need the raw failure body for custom error mapping (`BirthdateRepository`, `VenueCheckinRepository`).
- **Web — `src/lib/supabase/require-user.ts`**: `requireUser(request)` wraps Bearer-token parse → env check → service-role client → `auth.getUser()`, returning `{ok, supabase, user}` or a ready `NextResponse`. Used by the 7 privileged routes (passes, referral/code, referral/attribute, transactions, wallet/topup, wallet/spend, account/delete). **Not** for the cookie-session routes (events, promos and their `[id]` variants) — those get their user from RLS via `@/lib/supabase/server`.

### Navigation
- `RootView` manages splash, onboarding, auth, and main app
- `MainTabView`: Tonight (0), Explore (1), Trips (2), Plan (3), Profile (4)
- `RootView` overlays: Priority Entry hub, Cart sheet, Offline banner, Order confirmation
- Trip views: `TripsListView` → sheet → `PromptYourNightView` (create from vibe) or `TripDetailView` (view/edit)
- Plan tab: `PlanView` with prompt → `NightPlan` generation + save

### Tab Bar (5 tabs)
| Tab | Icon | View | Dependencies |
|-----|------|------|-------------|
| Tonight | `flame.fill` | `TonightView` | `VenueStore`, `AppState` |
| Explore | `map.fill` | `ExploreView` | `VenueStore` |
| Trips | `suitcase.fill` | `TripsListView` | `VenueStore`, `TripStore` (internal) |
| Plan | `sparkles` | `PlanView` | `VenueStore`, `AppState` |
| Me | `person.fill` | `ProfileView` | `AppState` |

---

## Key Files

```
barpass/
├── CLAUDE.md                              ← este archivo
├── barpass-miami.html                     ← web app legacy (WebView)
├── barpass-v2/                            ← Next.js v2 app
│   ├── supabase/schema.sql                ← tablas (venues, events, profiles, favorites, night_plans, trips)
│   ├── scripts/enrich-venues.ts           ← Google Places seed
│   └── src/                               ← App Router pages, features, components
└── BarPass-iOS/BarPass/
    ├── Resources/
    │   ├── DesignSystem.swift              ← Colores, radii, spacing, haptics, shimmer, glass, BarPassLogo
    │   ├── PrivacyInfo.xcprivacy           ← iOS 17+ privacy manifest
    │   ├── VenueLogos.swift               ← Logo URL resolver
    │   ├── venue_logos.json               ← Logo URL mappings
    │   └── venue_media.json               ← Venue media metadata
    ├── Models/
    │   ├── Venue.swift                    ← BarPassVenue, VenueEvent, PopularDrink
    │   ├── VenueStore.swift               ← @MainActor, repository injected
    │   ├── Trip.swift                     ← Trip, Stop, TripStore, UserReputation, TripRating
    │   └── NightPlan.swift                ← NightPlan, PlanStop
    ├── Repositories/
    │   ├── VenueRepository.swift           ← Protocol (7 methods)
    │   ├── LocalVenueRepository.swift     ← Actor, fallback with .preview
    │   ├── SupabaseVenueRepository.swift  ← Actor, real Supabase fetch + row mapping
    │   ├── TripRepository.swift           ← Protocol (CRUD)
    │   ├── SupabaseTripRepository.swift   ← Live, real Supabase (trips_schema.sql) — used by RepositoryDependencies
    │   ├── PlanRepository.swift           ← Protocol + LocalPlanRepository (actor)
    │   ├── SupabasePlanRepository.swift   ← Placeholder (throws)
    │   └── RepositoryDependencies.swift   ← DI point (venue, trip, plan)
    ├── Core/Services/
    │   ├── AuthService.swift              ← Native Supabase Auth (URLSession, no SDK)
    │   ├── ImageCache.swift               ← NSCache hot/standard + CachedImage view
    │   ├── HapticService.swift           ← Not used (BPHaptics in DesignSystem)
    │   ├── LocationService.swift          ← Location permissions + fetch
    │   ├── NotificationService.swift      ← Push notification registration
    │   └── ApplePayService.swift          ← Apple Pay stub
    ├── Core/Networking/APIClient.swift    ← URLSession-based API client
    ├── Core/Cache/CacheManager.swift      ← Cache management
    ├── Core/Config/StripeConfig.swift     ← Stripe publishable key
    ├── Features/
    │   ├── Main/MainTabView.swift         ← 5-tab native tab bar
    │   ├── RootView.swift                 ← Root coordinator (splash, auth, sheets, overlays)
    │   ├── Tonight/
    │   │   ├── TonightView.swift          ← Home feed with venue cards
    │   │   ├── VenueDetailView.swift      ← Venue detail with events, drinks, pass buy
    │   │   └── EventFlyerCard.swift       ← Posh/Dice-inspired flyer card
    │   ├── Explore/ExploreView.swift      ← Map + venue list
    │   ├── Trips/
    │   │   ├── TripsListView.swift        ← Trip cards, empty state, create/detail sheets
    │   │   ├── TripCreateFlow.swift       ← 4-step creation wizard
    │   │   ├── TripDetailView.swift       ← Itinerary, members, join, rate, complete
    │   │   ├── PromptYourNightView.swift  ← Vibe chips + NL prompt → route builder
    │   │   ├── NightPlanner.swift         ← Scoring engine (multi-signal, events, open-now, trending)
    │   │   └── TripSocial.swift           ← JoinRequestModal, ReputationBadgeView, RatingPrompt
    │   ├── Plan/PlanView.swift            ← AI concierge prompt → NightPlan generation
    │   ├── Auth/NativeAuthView.swift      ← Email/password sign in/up, forgot password sheet
    │   ├── Cart/                          ← CartView, CartStore, CardPaymentView (Stripe UI stub)
    │   ├── PriorityEntry/                 ← Hub, SkipLine, Table, Tickets, QR confirm
    │   ├── Profile/ProfileView.swift      ← Points, level, stats, how-to-earn
    │   ├── Splash/SplashView.swift        ← 0.3s spring → 0.6s auto-dismiss
    │   └── Onboarding/OnboardingVideoView.swift ← Video splash (placeholder)
    ├── AppState.swift                     ← ObservableObject (Auth app state, sheets, connectivity)
    ├── BarPassApp.swift                   ← @main, AppDelegate (push, deep links, BG tasks)
    └── BarPass app.xcodeproj              ← Xcode project (Swift 6, iOS 17+)
```

---

## Design System — Deep Cosmos

Universal design for all audiences.

```swift
// Colors (in Color extension, DesignSystem.swift)
bpAmber          = Color(red: 0.92, green: 0.72, blue: 0.28)
bpAmberBright    = Color(red: 0.98, green: 0.86, blue: 0.50)
bpSurface        = Color(white: 0.06)
bpGreen          = Color(red: 0.2, green: 0.9, blue: 0.4)
bpDanger         = Color(red: 1, green: 0.42, blue: 0.42)
bpCardBackground = Color(red: 0.06, green: 0.04, blue: 0.10)
bpTextSecondary  = Color.white.opacity(0.4)
bpTextTertiary   = Color.white.opacity(0.25)
bpBorder         = Color.white.opacity(0.07)

// Fonts
bpLargeTitle() = .system(size: 30, weight: .black, design: .rounded)
bpTitle1()     = .system(size: 24, weight: .black, design: .rounded)
bpTitle2()     = .system(size: 20, weight: .bold)
bpHeadline()   = .system(size: 17, weight: .bold)
bpBody()       = .system(size: 15)
bpCaption()    = .system(size: 12, weight: .semibold)
bpSmall()      = .system(size: 11)
bpTiny()       = .system(size: 8, weight: .heavy)

// Spacing
BPSpacing = { xs: 4, sm: 8, md: 14, lg: 20, xl: 28 }
BPRadius  = { sm: 10, md: 14, lg: 16, xl: 20, xxl: 24 }

// Modifiers
bpEntrance(offset:delay:)  — Spring entrance animation
bpAccessibility(label:hint:isButton:)  — VoiceOver wrapper
shimmer()  — Skeleton shimmer
glass()  — Ultra-thin material glassmorphism

// Logo
BarPassLogo(subtitle:) → "BAR" (white) + "PASS" (amber) + amber underline

// Haptics
BPHaptics.{light, medium, heavy, selection, success, error}
```

---

## Auth Flow

```
App Launch
  ↓ restoreSession() sync from UserDefaults
  ↓ success? → completeAuth() (showActionBar = true)
  ↓ fail?    → showNativeAuth = true (email/password form)
  
Sign In / Sign Up
  ↓ POST /auth/v1/token?grant_type=password (or signup)
  ↓ session saved to UserDefaults
  ↓ completeAuth()

Forgot Password
  ↓ Dark sheet (340pt), amber accent
  ↓ POST /auth/v1/recover
  ↓ Success state with auto-dismiss

Sign Out
  ↓ AuthService.shared.signOut()
  ↓ UserDefaults.removeObject
  ↓ showNativeAuth = true
```

---

## Session Status (Jul 10, 2026)

### ✅ COMPLETED — Full Project Reconstruction (Jul 10)

**Incident:** `git clean -fd` deleted ~18 untracked files (Jul 10 session). All files recreated from memory across 3 sessions.

**Files recreated:**
- `AuthService.swift`, `ImageCache.swift`, `DesignSystem.swift`, `PrivacyInfo.xcprivacy`
- All `Repositories/` (VenueRepository, LocalVenueRepository, SupabaseVenueRepository, TripRepository, LocalTripRepository, SupabaseTripRepository, PlanRepository, LocalPlanRepository, SupabasePlanRepository, RepositoryDependencies)
- `Models/Trip.swift`, `Models/NightPlan.swift`
- `Features/Trips/NightPlanner.swift`, `PromptYourNightView.swift`, `TripSocial.swift`, `TripsListView.swift`, `TripCreateFlow.swift`, `TripDetailView.swift`
- `Features/Tonight/EventFlyerCard.swift`
- `Resources/VenueLogos.swift`, `venue_logos.json`, `venue_media.json`

### ✅ COMPLETED — Build Fixes
- `AuthError` moved from nested to top-level type (broke `NativeAuthView` catch block)
- `AuthMetrics` struct added to `NativeAuthView`
- Duplicate `BPHaptics.success()` private extension removed
- `nonisolated(unsafe)` removed from `VenueStore.let repository` (warning fix)
- All packages resolved (Stripe SPM 23.32.0)
- **0 errors, 0 warnings in Release build**
- Stale `barpass/` duplicate directory removed

### ✅ COMPLETED — Previous Sessions (Jul 6)

- Repository architecture migration (protocol + actor pattern)
- Venue model rename (`Venue` → `BarPassVenue`)
- Login performance optimization (~0.5-0.8s vs previous 5-12s)
- Supabase backend + admin panel + 176 venues seeded
- Image downsampling via ImageIO + CachedImage + targetSize
- Stripe SPM package resolved
- Forgot password with custom dark sheet
- Design System expansion (fonts, entrance, accessibility, shimmer)
- 0 Swift 6 warnings in Release

### ❌ PENDING / KNOWN ISSUES (actualizado 2026-07-14)

- **Stripe en Vercel** — `STRIPE_SECRET_KEY` ya está en `.env.local` (test, verificada), pero **falta agregarla en Vercel** (Settings → Environment Variables, los 3 environments, + redeploy). Hasta entonces `/api/transactions` y `/api/wallet/topup` siguen devolviendo 503 `payments_not_configured` en producción.
- **Stripe live** — bloqueado por los papeles de constitución de la empresa (la cuenta no está activada, `charges_enabled: false`). No es trabajo de código.
- **Build de TestFlight desactualizada** — la build subida apunta a la cuenta de Stripe vieja; hay que recompilar para que tome la `pk_test_` corregida.
- **NVIDIA key** — missing (local and Vercel). AI Concierge (`/api/concierge`, NVIDIA NIM/Llama 3.3) always 503s `ai_not_configured` until set. See **Plan Consolidation Roadmap** below — this key is a hard prerequisite for Phase C3.
- **Onboarding videos** — 6 Higgsfield clips not yet generated. View is placeholder.
- **MapLibre** — works locally but not deployed.
- **Supabase night_plans table** — `SupabasePlanRepository` is live and wired (`RepositoryDependencies.plan`), not a placeholder — corrected 2026-09-01, see Key Files table above. Trips are NOT disk-only either — `SupabaseTripRepository` is live against `trips_schema.sql` (verified against the real DB 2026-08-22); the old disk-based `LocalTripRepository` was deleted 2026-08-27 (confirmed zero references — dead code from the migration).
- **PrivacyInfo.xcprivacy** — declares collected data but may need App Store review confirmation.

---

## Plan Consolidation Roadmap (2026-09-01)

### El problema
Tres superficies distintas resuelven hoy el mismo job ("dame un plan para esta noche a partir de un prompt/vibe"), sin comunicarse entre sí, más un backend de IA ya desplegado que ninguna de las tres usa:

| Dónde | Qué hace | Motor |
|---|---|---|
| `Features/Plan/PlanView.swift` (tab 3) | 1 prompt → 1 `NightPlan` | Local (`NightPlan.sample`, `Core/Intelligence/ExperienceScorer.swift`/`DiscoveryScorer.swift`) |
| `Features/Trips/PromptYourNightView.swift` + `NightPlanner.swift` (dentro de `TripsListView`) | chips de vibe + company type + prefs inclusivas + prompt → ruta de `PlannedStop` | Local, motor y modelo de datos distintos al de Plan |
| `Features/Tonight/PromptYourNightHomeSection.swift` (dentro de `TonightView`, también disparado por el deep link `.tonightPrompt` / widget) | entrada promocional al mismo concepto | — |
| `barpass-v2/src/app/api/concierge/route.ts` (desplegado en Vercel) | prompt → `NightPlan` generado por LLM real, con rate limit (10/min/IP), retry, validación Zod | **NVIDIA NIM, Llama 3.3 70B** — nunca llamado desde iOS |

Además hay dos shapes de `NightPlan` incompatibles en el mismo producto: el local de iOS (`PlanStop{time, venueName, venueNeighborhood, venuePriceRange, note}`, `totalEst`/`aiInsight` como strings) y el del concierge/web (`PlanStop{time, venueSlug, venueName, note, estimatedSpend}`, `totalEstimate` numérico, `insiderTip`).

### Decisiones tomadas
1. **Alcance de este round:** unificar UI + datos **y** cablear el concierge real (no solo reorganizar pantallas).
2. **Schema canónico:** el del concierge/web (`venueSlug`, `estimatedSpend` numérico, `insiderTip`, `summary`) — ya referencia venues reales por slug (`BarPassVenue.slug` ya existe) y es el que produce IA de verdad. El modelo Swift local (`Models/NightPlan.swift`) se adapta a este shape, no al revés.
3. **`Features/Plan` es la superficie única.** `PromptYourNightView.swift` y `NightPlanner.swift` (Trips) se eliminan; su funcionalidad (vibe chips, company type, prefs inclusivas) se fusiona dentro de `PlanView`. `PromptYourNightHomeSection.swift` (Tonight) se elimina también.
4. **Trips conserva "Guardar como Trip"** como acción posterior sobre un `NightPlan` ya generado (reutiliza `TripRepository`/`TripCreateFlow`), no como su propio flujo de generación.
5. **Sin migración de datos** — pre-lanzamiento, no hay usuarios reales con `night_plans`/trips generados por el flujo viejo que preservar. La columna `plan` en `public.night_plans` es `jsonb`, así que no requiere `ALTER TABLE`; simplemente empieza a guardar el nuevo shape.

### Schema canónico (Swift + Supabase)
```swift
struct PlanStop: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    let time: String
    let venueSlug: String
    let venueName: String
    let note: String
    let estimatedSpend: Double
}

struct NightPlan: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var title: String
    var summary: String
    var stops: [PlanStop] = []
    var totalEstimate: Double
    var insiderTip: String
    var createdAt: Date = .now
}
```
`public.night_plans.plan` (jsonb) simplemente empieza a almacenar este shape — sin migración SQL. `barpass-v2/src/types/plan.ts` y `plan-schema.ts` ya son la fuente de verdad; no cambian.

### Checklist de implementación (pendiente — no ejecutado aún)
- [x] **C1 — Schema** (2026-09-01): `Models/NightPlan.swift` reescrito al shape canónico (`venueSlug`, `estimatedSpend`, `totalEstimate`, `insiderTip`, `summary`). `SupabasePlanRepository`/`LocalPlanRepository` sin cambios de código — siguen siendo Codable pass-through, el shape nuevo simplemente empieza a viajar dentro. `ShareManager.shareNightPlan` sin cambios (solo usa `time`/`venueName`, que no cambiaron de nombre).
- [x] **C2 — Merge de UI** (2026-09-01): vibe chips (`ExperienceIntent`), `CompanyType` y prefs inclusivas portados de `PromptYourNightView.swift` a `PlanView.swift` (nueva `contextPicker`). Generar con solo chips (sin texto) sigue funcionando como en el flujo viejo — `effectivePrompt()` sintetiza un prompt desde los chips cuando el campo de texto está vacío.
- [x] **C3 — Conectar IA real** (2026-09-01): `APIClient.fetchConciergePlan(prompt:budget:groupSize:neighborhood:excludeSlugs:)` nuevo, `POST /api/concierge`. `generatePlan()` en `PlanView` intenta el concierge primero; cualquier falla (`notConfigured`/`rateLimited`/`invalidRequest`/`unavailable`/red) cae silenciosamente a `NightPlan.local` (el motor `ExperienceScorer`, ya no `NightPlan.sample`). **Sigue bloqueado en producción hasta setear `NVIDIA_API_KEY`** (ver Known Issues arriba) — mientras tanto usa siempre el fallback local, que ahora sí incorpora vibe/company/inclusive context vía `ExperienceScorer`.
- [x] **C4 — Retiro de duplicados** (2026-09-01): `PromptYourNightView.swift` y `PromptYourNightHomeSection.swift` borrados (código y referencias en `project.pbxproj`). `NightPlanner.swift` **no** se borró completo — `phase(of:)` lo usa `Stop.sequence` (Trip.swift) y `vibes` lo usa `ExperienceScorer`; solo se borró `NightPlanner.plan()`/`PlannedStop`, que ya nadie llama. `TripsListView`'s "AI" choice ahora navega a Plan (`appState.requestedTab = 3`) en vez de abrir su propio sheet; `createTrip()` (dead code, único caller era ese sheet) también se borró. `TonightView` perdió el flag `usePromptYourNightHome` y volvió a su texto pasivo (`home.where`) sin condicional.
- [x] **C5 — "Guardar como Trip"** (2026-09-01): botón nuevo en `NightPlanView` (`PlanView.swift`) — `saveAsTrip()` matchea `PlanStop.venueSlug` contra `venueStore.venues`, arma `Stop.sequence(...)` y guarda vía `RepositoryDependencies.trip.saveTrip(...)`, con el mismo award de puntos/analytics que tenía `TripsListView.createTrip`.
- [x] **C6 — Navegación** (2026-09-01): `DeepLinkRoute.tonightPrompt` renombrado a `.planPrompt` (mismo `barpass://prompt`); `MainTabView.handleDeepLink` ahora hace `selectedTab = 3` en vez de tocar `appState.focusPromptRequested` (propiedad borrada de `AppState.swift`, ya no tenía consumidor).
- [x] **C7 — Supabase** (2026-09-01): sin `ALTER TABLE` (jsonb, confirmado). Comentario junto a `night_plans` en `barpass-v2/supabase/schema.sql` actualizado con el shape canónico.

**Verificado:** `xcodebuild -scheme BarPass -destination 'generic/platform=iOS Simulator'` → `** BUILD SUCCEEDED **`, cero errores (2026-09-01).

### Explícitamente fuera de este round
La arquitectura de chat conversacional Free/Premium de `BARPASS_PLAN_CHAT_DEVELOPER_DOCS/` (intent resolver, `ConversationContext`, usage ledger por usuario, StoreKit/entitlement, feature flags) **no se toca aquí** — ninguno de esos sistemas existe hoy en el repo (verificado, cero coincidencias de StoreKit/feature-flags). Este consolidation round es el prerequisito de infraestructura; la Fase 1 del chat (`08_DEVELOPER_TASKS.md`) empieza después, sobre una única superficie y un único schema ya limpios.

---

## Plan Chat Architecture (Fase 1, 2026-09-02)

Construido sobre la superficie ya consolidada arriba. `Features/Plan/PlanView.swift` pasó de "un prompt → un resultado" a una conversación multi-turno real, siguiendo 02_UX_ARCHITECTURE.md/03_CHAT_ENGINE.md de `BARPASS_PLAN_CHAT_DEVELOPER_DOCS/`.

### Decisiones tomadas
1. **Chat multi-turno real** — lista de mensajes + composer persistente, no un formulario. Los quick actions ("Más exclusivo"/"Más económico"/"Más cerca"/"Más social") refinan el plan actual en la misma conversación en vez de generar uno nuevo desde cero.
2. **Persistencia en Supabase desde ya** — tabla nueva `public.plan_conversations`, mismo patrón jsonb-blob-por-fila que `night_plans`.
3. **Premium con stub visual** — hay una pantalla de upgrade (`PlanUpgradeSheet.swift`), pero **sin StoreKit ni cobro real** — el CTA dice "Muy pronto" a propósito. No hay ningún gate de verdad: todo el mundo usa el mismo motor Free hoy.

### Modelo (`Models/PlanConversation.swift`)
```swift
struct PlanMessage { role: .user | .assistant, text, plan: NightPlan?, quickActions: [String] }
struct PlanConversation { title, messages: [PlanMessage], currentPlan: NightPlan?, createdAt, updatedAt }
```
Contrato de respuesta único (`message, cards≈plan.stops, quickActions, plan`) — la UI nunca distingue si `plan` vino del concierge o del fallback local, tal como pide 03_CHAT_ENGINE.md.

### Motor (`Core/Intelligence/PlanEngine.swift`)
`PlanEngine.respond(enginePrompt:conversation:context:venues:userLocation:)` intenta `APIClient.fetchConciergePlan` (pasando `excludeSlugs` de las venues ya usadas en la conversación, para no repetir) y cae a `NightPlan.local` en cualquier falla — mismo fallback silencioso que ya existía. `PlanEngine.refinementActions` define los 4 quick actions post-plan; `PlanEngine.welcomeMessage()` arma el primer mensaje con las sugerencias de siempre (`plan.suggestion.*`) como quick actions.

### Persistencia (`Repositories/ConversationRepository.swift`, `SupabaseConversationRepository.swift`)
Mismo patrón que `PlanRepository`/`SupabasePlanRepository`: `LocalConversationRepository` (disco, fallback de invitados) + `SupabaseConversationRepository` (real, requiere sesión, RLS por `auth.uid()`). `RepositoryDependencies.conversation` ya apunta al Supabase real. Cada turno se auto-guarda local siempre, y a Supabase en silencio si hay sesión (sin banner de error para invitados — eso solo se muestra en acciones explícitas como "Save"/"Save as Trip").

### ⚠️ Pendiente manual — igual que `night_plans`/`trips` en su momento
La tabla `plan_conversations` está en `barpass-v2/supabase/schema.sql` pero **no se ejecutó contra el proyecto real de Supabase** — el MCP de Supabase conectado en esta sesión apunta a otro proyecto ("ByPark"), no al de BarPass, así que no había forma de aplicarla en vivo. Hay que correr ese bloque de `schema.sql` en el SQL editor de Supabase antes de que la persistencia de conversaciones funcione para usuarios reales (mientras tanto, `SupabaseConversationRepository` simplemente falla y el guardado local sigue funcionando).

### Copy del encabezado — reconciliado con origin/main (2026-09-02)
Se intentó cambiar `plan.headerTitle` a "Crea tu noche" a pedido explícito ("concierge" sonaba raro en español), pero **origin/main ya tenía un cambio de Sebastián/Opus 5 en el mismo lugar** ("Give Remy's greeting some variety instead of the same line every time") que reemplazó el título/subtítulo fijo por **6 variantes rotativas por idioma** (`plan.headerTitle.0`–`.5`, `plan.headerSubtitle.0`–`.5`), elegidas una vez por sesión con `@State private var greetingIndex = Int.random(in: 0..<6)`. Se decidió **adaptar el chat a su rotación en vez de pisarla**: `plan.headerTitle`/`plan.headerSubtitle` (sin sufijo) quedaron con su texto original — ya no se usan en ningún lado, es el `.0` legacy — y `PlanView`'s header + `PlanEngine.welcomeMessage(greetingIndex:)` (primera burbuja del chat) ahora comparten el mismo `greetingIndex`, así que el título del header y el primer mensaje de Remy siempre son la misma variante, no dos saludos distintos.

---

## Product Readiness Checklist (actualizado 2026-07-14)

### 🔴 Crítico (blocker para cobrar)
- [x] **Backend de pagos** — `/api/transactions` real (Stripe PaymentIntent + Supabase `orders`), deployado en `barpass-v2.vercel.app`
- [x] **Wallet top-up** — `/api/wallet/topup` + `/api/wallet/spend`, balance atómico en Supabase
- [x] **Privacy Policy + Terms of Service** — `/legal/privacy`, `/legal/terms`, linkeados desde el login
- [x] **Verificación de edad 21+** — `AgeGateView`, bloqueante, post-login
- [x] **Stripe test** — `STRIPE_SECRET_KEY` seteada local, cobro de prueba verificado ($25 `succeeded`)
- [ ] **Stripe en Vercel** — falta agregar `STRIPE_SECRET_KEY` + redeploy
- [ ] **Stripe live** — bloqueado por papeles de la empresa (no es código)
- [x] **Apple Pay** — merchant ID `merchant.com.barpass.app` registrado + capability habilitada en Xcode (confirmado 2026-08-27)
- [x] **Apple Sign In** — capability habilitada en Xcode (confirmado 2026-08-27)

### 🟡 Importante (App Store)
- [x] Apple Developer account activa ($99/año) — **ACTIVA desde 2026-07-14**
- [x] QR único por orden + validación en venue (`/validate`, tabla `passes`, redención atómica)
- [x] Sistema de órdenes en Supabase (no Firestore)
- [ ] Screenshots (6.7" y 6.1")
- [ ] TestFlight

### 🟢 Post-lanzamiento
- [x] Historial de órdenes (`OrderHistoryView` en Profile)
- [x] Dashboard para venues (`/dashboard`)
- [x] Recordatorios locales (pase por vencer, mesa por empezar) — sin APNs
- [ ] Push notifications remoto (FCM/APNs) — bloqueado por certificado APNs (Xcode + portal)
- [ ] Crashlytics + Analytics
- [ ] TestFlight
- [ ] Ejecutar `schema.sql` en Supabase SQL editor para crear tablas `trips`/`stops`/`night_plans`

---

## Connected Tools

- **Figma** — <EMAIL> (Starter)
- **Higgsfield** — connected, needs credits
- **GitHub** — sebastianherrera7305-sys/barpass-miami
- **Firebase (legacy)** — barpass-app
- **Vercel** — <VERCEL_PROJECT_NAME> (broken)
- **Supabase** — `<PROJECT_REF>` (tables: venues, events, profiles, favorites)

---

*Última actualización: 2026-09-01*
