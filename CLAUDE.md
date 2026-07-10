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
**Stripe SPM:** `stripe-ios@23.32.0` resolved in pbxproj, CardPaymentView still uses stub.

---

## Architecture

### iOS (Swift 6, iOS 17+) — FULL NATIVE
```
Splash → Onboarding Video → Native Auth → MainTabView (5 tabs)
```

| Layer | Directory | Description |
|-------|-----------|-------------|
| **Domain Models** | `Models/` | `BarPassVenue`, `VenueType`, `Trip`, `NightPlan`, `CartItem`, `EventTicket`, `SkipLinePass`, `TableReservation` |
| **Repositories** | `Repositories/` | `VenueRepository`, `TripRepository`, `PlanRepository` (protocols). `SupabaseVenueRepository` (actor), `LocalVenueRepository`, `LocalTripRepository`, `LocalPlanRepository`, `SupabasePlanRepository` (placeholder), `SupabaseTripRepository` (placeholder) |
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
    │   ├── SupabaseTripRepository.swift   ← Placeholder (throws)
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

### ❌ PENDING / KNOWN ISSUES

- **Vercel v2 deployment** — middleware.ts uses deprecated pattern for Next.js 16. All routes return 500.
- **Stripe** — SPM added but `CardPaymentView` uses stub payment method. No real tokenization.
- **Apple Sign In capability** — not enabled in Xcode. Code in `NativeAuthView` expects it.
- **OpenAI key** — missing. AI Concierge (`/api/concierge`) won't work.
- **Onboarding videos** — 6 Higgsfield clips not yet generated. View is placeholder.
- **MapLibre** — works locally but not deployed.
- **Supabase trips/night_plans tables** — `SupabaseTripRepository` and `SupabasePlanRepository` are placeholders. Trips persist on disk only.
- **Apple Pay** — placeholder merchant ID `merchant.com.barpass.app`.
- **PrivacyInfo.xcprivacy** — declares collected data but may need App Store review confirmation.
- **Remove `AppleSignInHelpers.swift` and `ApplePayHelpers.swift`** — if they still exist as dead references.

---

## Product Readiness Checklist

### 🔴 Crítico (blocker para cobrar)
- [ ] **Stripe SDK** — código listo en `CardPaymentView.swift`. Tokenización real pendiente.
- [ ] **Apple Pay** — merchant account verificado
- [ ] **Wallet top-up** — pago real
- [ ] **Apple Sign In** — habilitar capability en Xcode + configurar en Apple Developer portal
- [ ] **Privacy Policy + Terms of Service** — URLs públicas
- [ ] **Verificación de edad** — 21+

### 🟡 Importante (App Store)
- [ ] Apple Developer account activa ($99/año)
- [ ] Screenshots (6.7" y 6.1")
- [ ] QR único por orden + validación en venue
- [ ] Sistema de órdenes en Supabase (no Firestore)

### 🟢 Post-lanzamiento
- [ ] Push notifications (FCM)
- [ ] Historial de órdenes
- [ ] Dashboard para venues
- [ ] Crashlytics + Analytics
- [ ] TestFlight
- [ ] Ejecutar `schema.sql` en Supabase SQL editor para crear tablas `trips`/`stops`/`night_plans`

---

## Connected Tools

- **Figma** — sebastianherrera7305@gmail.com (Starter)
- **Higgsfield** — connected, needs credits
- **GitHub** — sebastianherrera7305-sys/barpass-miami
- **Firebase (legacy)** — barpass-app
- **Vercel** — barpass-v2 (broken)
- **Supabase** — `hrhdezziddfrktvtgzbg` (tables: venues, events, profiles, favorites)

---

*Última actualización: 2026-07-10*
