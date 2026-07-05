# BarPass — Project Intelligence

> This file is auto-loaded every session. Keep it updated as the project evolves.

---

## What is BarPass

Miami nightlife access app. Users buy Skip the Line passes, VIP tables, event tickets, and order drinks — all from their phone. Target: anyone who goes out, universal design for all nationalities/demographics.

**Bundle ID:** `com.sebastian.barpass`
**GitHub:** `https://github.com/sebastianherrera7305-sys/barpass-miami`
**Web (GitHub Pages):** `https://sebastianherrera7305-sys.github.io/barpass-miami/barpass-miami.html`
**Firebase project:** `barpass-app` · apiKey `AIzaSyB4uz5CaLCC3nsLz3QwOJtfp1bnBUqQUlg`

---

## Architecture

```
Splash → Onboarding Video → Native Auth → WebView (main app)
```

- **Native Swift** — all screens above the WebView
- **WebView** — venue list, venue detail, menus (barpass-miami.html)
- **NativeBridge** — JS ↔ Swift communication
- **Firebase Auth** — authentication (web SDK, injected via JS)
- **Firestore** — user data, orders, wallet
- **Vercel API** — payment processing endpoint
- **Apple Pay** — merchant.com.barpass.app

---

## Screen Inventory

| # | Screen | File | Status |
|---|--------|------|--------|
| 1 | Splash | `Features/Splash/SplashView.swift` | ✅ Redesigned |
| 2 | Onboarding Video | `Features/Onboarding/OnboardingVideoView.swift` | ✅ Built (needs video clips) |
| 3 | Auth / Login | `Features/Auth/NativeAuthView.swift` | ✅ Redesigned |
| 4 | Home / Venues | `barpass-miami.html` (WebView) | 🔄 Web |
| 5 | Venue Detail | `barpass-miami.html` (WebView) | 🔄 Web |
| 6 | Cart | `Features/Cart/CartView.swift` | ✅ Redesigned |
| 7 | Card Payment | `Features/Cart/CardPaymentView.swift` | ⚠️ UI only, no Stripe |
| 8 | Priority Entry Hub | `Features/PriorityEntry/PriorityEntryHubView.swift` | 🔜 Pending redesign |
| 9 | Skip the Line | `Features/PriorityEntry/SkipLinePassView.swift` | 🔜 Pending redesign |
| 10 | Mesa VIP | `Features/PriorityEntry/TableReservationView.swift` | 🔜 Pending redesign |
| 11 | Event Tickets | `Features/PriorityEntry/EventTicketsView.swift` | 🔜 Pending redesign |
| 12 | Active Ticket (QR) | `Features/PriorityEntry/ActiveTicketView.swift` | 🔜 Pending redesign |
| 13 | Active Pass (QR) | `Features/PriorityEntry/ActivePassView.swift` | 🔜 Pending redesign |

---

## Design System — Deep Cosmos

Universal design for all audiences (all nationalities, ages, cultures).

```swift
// Colors
let bg     = Color.black
let surface = Color(white: 0.06)
let amber  = Color(red: 0.92, green: 0.72, blue: 0.28)
let amberB = Color(red: 0.98, green: 0.86, blue: 0.50)
let textPrimary   = Color.white
let textSecondary = Color.white.opacity(0.4)
let border        = Color.white.opacity(0.08)

// Corner radius
let cardRadius: CGFloat = 20
let fieldRadius: CGFloat = 14
let buttonRadius: CGFloat = 16

// Typography
// Title: .system(size: 22, weight: .bold)
// Body:  .system(size: 15, weight: .regular)
// Caption: .system(size: 12)
// Label: .system(size: 11, weight: .heavy) + tracking(4) uppercase
```

---

## Onboarding Video Sequence (Higgsfield)

6 clips to generate, name exactly as shown and place in `BarPass-iOS/BarPass/Resources/Onboarding/`:

| File | Scene | Prompt |
|------|-------|--------|
| `scene1.mp4` | Three amber orbs | `Three glowing amber orbs floating in black void. Soft pulse. Volumetric light. No movement. 3 sec.` |
| `scene2.mp4` | Sports bar | `Macro shot. Sweating cold beer glass on bar counter. Big screen TV with football game blurred in background. Cheering crowd bokeh. Warm light. 3 sec.` |
| `scene3.mp4` | Festival | `Wide shot. Massive outdoor music festival at night. Laser lights cutting through crowd. Miami heat haze. Aerial slowly descending. Diverse crowd hands up. 4 sec.` |
| `scene4.mp4` | La oliva | `Extreme macro. Single green olive falling slow motion into crystal martini glass. Perfect liquid splash. Black background. Amber backlight. 4 sec.` |
| `scene5.mp4` | Club VIP | `Slow dolly through VIP section. Bottle service with sparklers. DJ booth with crowd below. Neon lights. Miami nightclub. Cinematic luxury. Diverse glamorous crowd. 4 sec.` |
| `scene6.mp4` | QR Access | `Close-up hands holding phone. Golden QR code on screen. Velvet rope opens. POV entering VIP. Slow motion. 3 sec.` |

Aspect ratio: **9:16** · Model: **Kling 3.0** · Muted audio

---

## Product Readiness Checklist

### 🔴 Crítico (blocker para cobrar)
- [x] Stripe SDK en CardPaymentView — código listo (tokeniza con `STPPaymentCardTextField`, llama a `POST /transactions`). Falta: (1) agregar el paquete SPM `stripe-ios` en Xcode, (2) poner la publishable key real en `StripeConfig.swift`
- [ ] Apple Pay merchant account verificado
- [ ] Wallet top-up con pago real
- [x] Apple Sign In (requerido por Apple) — código listo (`NativeAuthView.swift`, `NativeBridge.swift`, `AppleSignInHelpers.swift`). Falta: habilitar capability "Sign in with Apple" en Xcode (Signing & Capabilities) + configurarlo en el Apple Developer portal
- [x] Pantalla "Olvidé mi contraseña" — listo (alert nativo → `NativeBridge.sendPasswordReset` → `fbAuth.sendPasswordResetEmail`)
- [ ] Privacy Policy URL pública
- [ ] Terms of Service
- [ ] Verificación de edad 21+

### 🟡 Importante (App Store)
- [ ] Apple Developer account activa ($99/año)
- [ ] Screenshots para App Store (6.7" y 6.1")
- [ ] Firestore security rules
- [ ] Datos reales de venues (no hardcodeados)
- [ ] QR único por orden + validación en venue
- [ ] Sistema de órdenes grabado en Firestore

### 🟢 Post-lanzamiento
- [ ] Push notifications reales (FCM)
- [ ] Historial de órdenes del usuario
- [ ] Dashboard para venues
- [ ] Crashlytics + Analytics
- [ ] TestFlight con beta testers reales

---

## Key Files

```
barpass/
├── CLAUDE.md                          ← este archivo
├── barpass-miami.html                 ← web app principal
├── barpass-map.html                   ← mapa de venues
└── BarPass-iOS/BarPass/
    ├── AppState.swift                 ← estado global
    ├── BarPassApp.swift               ← entry point
    ├── Core/
    │   ├── Bridge/NativeBridge.swift  ← JS↔Swift bridge
    │   └── WebView/BarPassWebView.swift
    ├── Features/
    │   ├── Splash/SplashView.swift
    │   ├── Onboarding/OnboardingVideoView.swift
    │   ├── Auth/NativeAuthView.swift
    │   ├── Cart/                      ← CartView, CartStore, CardPaymentView
    │   └── PriorityEntry/             ← Hub, SkipLine, Table, Tickets, QR
    └── Models/
        ├── CartItem.swift
        ├── EventTicket.swift
        ├── SkipLinePass.swift
        └── TableReservation.swift
```

---

## Standing Rules (IMPORTANT)

1. **V2 web = Next.js** — el producto web V2 vive en `barpass-v2/` (Next.js App Router + TypeScript + Tailwind 4 + Supabase). Features nuevas de web van ahí como módulos en `src/features/`
2. **iOS = Swift nativo** — features de la app iOS van en Swift (`BarPass-iOS/`), nunca en HTML
3. El HTML legacy (barpass-miami.html etc.) — solo bug fixes, no features
4. Diseño Deep Cosmos — negro + amber (#ebb847), sin colores culturalmente específicos
5. Build target iOS: 17+, Swift 6
6. Supabase será el backend único — web y iOS consumen las mismas tablas (ver `barpass-v2/supabase/schema.sql`)

## BarPass V2 (barpass-v2/)

Lanzamiento 15 agosto: "The smartest nightlife companion in Miami".
- Stack: Next.js (App Router) · TS · Tailwind 4 · Supabase · OpenAI · TanStack Query · Framer Motion · Zod
- Arquitectura feature-based: `src/features/{venues,discover,ai,map}/` — cada módulo con sus components/hooks/services/types
- Regla clave: lecturas de venues SOLO via `features/venues/services/venue-service.ts` (swap a Supabase = 1 archivo)
- AI Concierge: `POST /api/concierge` (OpenAI server-side, output validado con Zod)
- Pendiente: llaves en `.env.local` (Supabase, OpenAI, Mapbox), correr `supabase/schema.sql`, deploy a Vercel

---

## Connected Tools

- **Figma** — sebastianherrera7305@gmail.com (Starter, View seat)
- **Higgsfield** — conectado, necesita créditos para generar
- **GitHub** — sebastianherrera7305-sys/barpass-miami
- **Firebase** — barpass-app project

---

*Última actualización: 2026-06-25*

