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
**Vercel Project:** `<VERCEL_PROJECT_ID>` (org `<VERCEL_ORG_ID>`) — **LIVE at `https://barpass-v2.vercel.app`** (deployed 2026-07-14). Env vars set on Vercel: NEXT_PUBLIC_SUPABASE_URL, NEXT_PUBLIC_SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY, VENUE_VALIDATION_SECRET. Still missing on Vercel: STRIPE_SECRET_KEY, OPENAI_API_KEY (add when available). iOS `APIClient.baseURL` points here now (old `barpass-miami.vercel.app` Express/Firestore backend was never deployed and is dead).
**Stripe SPM:** `stripe-ios@23.32.0` resolved in pbxproj, `CardPaymentView` does real client-side tokenization + calls `/api/transactions` (real Stripe PaymentIntent server-side) — needs `STRIPE_SECRET_KEY` set on Vercel to actually charge.
**Apple Developer Program:** ACTIVE (paid, 2026-07-14). Team ID `<APPLE_TEAM_ID>`. Entitlements (`BarPass.entitlements`) now wired into the build via `CODE_SIGN_ENTITLEMENTS`. Sign In with Apple code complete (`NativeAuthView` + `AuthService.signInWithApple`). **Remaining manual step:** enable Sign In with Apple / MusicKit / Apple Pay capabilities in Xcode → Signing & Capabilities (one-time, 2FA-gated, can't be done via CLI).

---

## Architecture

### iOS (Swift 6, iOS 17+) — FULL NATIVE
```
Splash → Onboarding Video → Native Auth → MainTabView (5 tabs)
```

| Layer | Directory | Description |
|-------|-----------|-------------|
| **Domain Models** | `Models/` | `BarPassVenue`, `VenueType`, `Trip`, `NightPlan`, `CartItem`, `EventTicket`, `SkipLinePass`, `TableReservation` |
| **Repositories** | `Repositories/` | `VenueRepository`, `TripRepository`, `PlanRepository` (protocols). `SupabaseVenueRepository` (actor), `LocalVenueRepository`, `LocalTripRepository`, `LocalPlanRepository`, `SupabasePlanRepository` (placeholder — `RepositoryDependencies` uses `LocalPlanRepository`), `SupabaseTripRepository` (**live, wired as the real dependency** — real shared backend against `trips_schema.sql`, not a placeholder) |
| **DI** | `Repositories/RepositoryDependencies.swift` | `nonisolated(unsafe) static var venue/trip/plan` — swap implementations one line |
| **Stores** | `Models/VenueStore.swift`, `Models/TripStore.swift` | `@MainActor`, `@Published`, repository injected via init |
| **UI** | `Features/` | `MainTabView` (5 tabs), `TonightView`, `ExploreView`, `TripsListView`, `PlanView`, `ProfileView`, `CartView`, `CardPaymentView`, PriorityEntry hub, Trip detail/creation flow |
| **Services** | `Core/Services/` | `AuthService`, `HapticService`, `LocationService`, `NotificationService`, `BiometricService`, `ApplePayService`, `WalletPassService`, `ImageCache` |
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
├── src/lib/supabase/ — client.ts, server.ts, config.ts
├── supabase/schema.sql
└── scripts/enrich-venues.ts  — Google Places enrichment
```

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
    │   ├── LocalTripRepository.swift      ← Actor, disk-backed JSON
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
    │   ├── BiometricService.swift         ← Face ID / Touch ID
    │   ├── ApplePayService.swift          ← Apple Pay stub
    │   └── WalletPassService.swift        ← Wallet PassKit stub
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
    │   ├── Onboarding/OnboardingVideoView.swift ← Video splash (placeholder)
    │   └── WalletPass/AppleWalletButton.swift ← Add to Apple Wallet button
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

- **Apple capabilities** — Sign In with Apple / MusicKit / Apple Pay tienen código completo pero necesitan habilitarse en Xcode → Signing & Capabilities (2FA-gated, manual, un solo click por capability). Team ID `<APPLE_TEAM_ID>` ya paga y listo.
- **Stripe live** — `STRIPE_SECRET_KEY` no está seteada ni local ni en Vercel. `/api/transactions`, `/api/wallet/topup` devuelven 503 `payments_not_configured` hasta que se agregue.
- **OpenAI key** — missing. AI Concierge (`/api/concierge`) won't work.
- **Onboarding videos** — 6 Higgsfield clips not yet generated. View is placeholder.
- **MapLibre** — works locally but not deployed.
- **Supabase night_plans table** — `SupabasePlanRepository` is a placeholder; `RepositoryDependencies` uses `LocalPlanRepository`, plans persist on disk only. Trips are NOT disk-only anymore — `SupabaseTripRepository` is live against `trips_schema.sql` (verified against the real DB 2026-08-22); `LocalTripRepository`'s old disk-based trips are orphaned since this migration.
- **Apple Pay merchant ID** — código apunta a `<MERCHANT_ID>` (ya no es placeholder), pero el merchant ID en sí todavía no está registrado en el portal.
- **PrivacyInfo.xcprivacy** — declares collected data but may need App Store review confirmation.

---

## Product Readiness Checklist (actualizado 2026-07-14)

### 🔴 Crítico (blocker para cobrar)
- [x] **Backend de pagos** — `/api/transactions` real (Stripe PaymentIntent + Supabase `orders`), deployado en `barpass-v2.vercel.app`
- [x] **Wallet top-up** — `/api/wallet/topup` + `/api/wallet/spend`, balance atómico en Supabase
- [x] **Privacy Policy + Terms of Service** — `/legal/privacy`, `/legal/terms`, linkeados desde el login
- [x] **Verificación de edad 21+** — `AgeGateView`, bloqueante, post-login
- [ ] **Stripe live** — falta pegar `STRIPE_SECRET_KEY` real (local + Vercel)
- [ ] **Apple Pay** — merchant ID registrado en el portal + capability habilitada en Xcode
- [ ] **Apple Sign In** — código listo, falta habilitar capability en Xcode (3 clicks)

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

*Última actualización: 2026-07-10*
