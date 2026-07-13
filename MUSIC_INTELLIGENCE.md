# BarPass Music Intelligence™ — Arquitectura y Visión

> Documento oficial de producto y arquitectura. Última actualización: 2026-07-12.
> Misión: **"Discover the sound. Find your people. Live the moment."**

---

## 0. Tesis

BarPass deja de ser una app de venues y se convierte en la plataforma que conecta
**lo que escuchás** con **dónde salís**. El moat no son los nombres ™ — es el
dataset que solo BarPass puede acumular: la correlación entre perfil musical y
asistencia física real (check-ins GPS ya existentes). Spotify sabe qué escuchás
pero no dónde salís; Resident Advisor sabe de eventos pero no qué escuchás.

**Principio rector: cero data inventada.** Si el usuario no conecta música, la
capa entera no aparece. Ningún score se muestra sin datos reales que lo
respalden.

**Principio de privacidad: procesamiento on-device.** La escucha cruda nunca
sale del teléfono. A Supabase solo sube el resumen (Passport). Esto es bandera
de marketing, cumplimiento y moat a la vez.

---

## 1. Arquitectura técnica

```
BARPASS APP
│
├── Music Intelligence Layer
│   │
│   ├── MusicSource (protocol)                 ← abstracción de proveedor
│   │     ├── AppleMusicSource (MusicKit)      ← MVP
│   │     ├── SpotifySource (OAuth top-items)  ← V2
│   │     ├── SoundCloudSource                 ← V3
│   │     └── YouTubeMusicSource / futuros     ← V3+
│   │
│   ├── Hype Engine (HypeScore.swift)          ← determinístico, swappable por ML
│   ├── Music Passport (modelo + store)        ← identidad musical persistida
│   ├── Venue Matching Engine                  ← señal en NightPlanner (ya existe)
│   ├── Recommendation Engine                  ← extiende NightPlanner multi-señal
│   └── Artist Discovery Engine                ← V2/V3 (tabla artists + snapshots)
│
├── Patrones existentes que se reutilizan
│   ├── Repository pattern (RepositoryDependencies como DI)
│   ├── Store @MainActor ObservableObject (como VenueStore/PointsEngine)
│   ├── Persistencia local-first (Application Support JSON)
│   └── XP/Misiones (Tastemakers se enchufa a PointsEngine)
```

### El contrato `MusicSource`

Cada proveedor implementa el mismo protocol. La app nunca sabe de qué servicio
vino la data:

```swift
protocol MusicSource: Sendable {
    var kind: MusicSourceKind { get }              // .appleMusic, .spotify…
    var isAvailable: Bool { get async }            // ¿instalado/configurado?
    func requestAuthorization() async -> MusicAuthStatus
    func snapshot(days: Int) async throws -> MusicSnapshot
}

struct MusicSnapshot {                             // normalizado entre proveedores
    let artists: [ArtistPlay]                      // nombre, plays aprox, géneros
    let genres: [GenreWeight]                      // género → peso 0…1
    let capturedAt: Date
    let source: MusicSourceKind
}
```

Reglas del contrato:
- Un adaptador que no puede dar un campo lo omite — **nunca lo estima**.
- `snapshot()` es la única fuente de verdad; el Passport se deriva de uno o
  más snapshots fusionados (multi-proveedor = merge por artista/género).
- Errores tipados: `.notAuthorized`, `.notEntitled` (falta capability),
  `.noData`, `.network` — la UI muestra estados honestos para cada uno.

### Hype Score (v1, determinístico y explicable)

```
HypeScore (0-100) =
  40% frecuencia de artistas top (concentración de plays)
+ 25% diversidad de géneros
+ 20% recencia (actividad últimos 7 días vs 30)
+ 15% descubrimientos (artistas nuevos esta semana)

Energía (0-100) = Σ peso(género) × energía(género)
  (EDM/techno/reggaeton = alta · hip-hop/pop/latin = media · jazz/lounge = baja
   — tabla transparente en código, no pseudo-IA)
```

Swappable: la firma `HypeEngine.compute(snapshot) -> HypeSummary` permite
reemplazar la implementación por un modelo entrenado cuando haya data.

### Venue Matching

`musicMatch(passport, venue) -> Double` cruza `passport.topGenres` con
`venue.musicGenres` (campo que ya existe en las 181 filas de Supabase).
Se integra como **una señal más** del scoring multi-señal de `NightPlanner`
y como badge visual ("🎵 87% match") en cards y detalle.

---

## 2. Modelo de datos

### On-device (Application Support, JSON — como Trips/Posts)

```
music_passport.json   → MusicPassport (ver abajo)
music_snapshots.json  → últimos N snapshots (para tendencia semanal)
```

```swift
struct MusicPassport: Codable {
    var topGenres: [GenreWeight]        // máx 5
    var topArtists: [String]            // máx 10
    var hypeScore: Int                  // 0-100
    var energy: Int                     // 0-100
    var nightPersonality: String        // derivado por reglas (ver §4)
    var newDiscoveries: [String]        // artistas nuevos esta semana
    var sources: [MusicSourceKind]
    var updatedAt: Date
}
```

### Supabase (aditivo — cero cambios a tablas existentes)

```sql
-- Resumen del passport (opt-in, para matching social futuro)
music_passports (
  user_id uuid primary key references auth.users(id),
  top_genres text[], top_artists text[],
  energy int, night_personality text,
  is_public boolean default false,
  updated_at timestamptz default now()
);
-- RLS: select propio (o is_public), insert/update solo auth.uid() = user_id

-- V2: catálogo de artistas + momentum honesto (Δ de snapshots PROPIOS)
artists          (id, name, genres text[], spotify_id, apple_id, image_url,
                  followers int, popularity int)
artist_snapshots (artist_id, followers, popularity, captured_at)
tastemaker_marks (user_id, artist_id, marked_at)   -- "lo descubrí primero"
```

`venues.music_genres` ya existe → el matching no necesita schema nuevo.

---

## 3. Módulos (archivos concretos)

| Archivo | Responsabilidad |
|---|---|
| `Core/Music/MusicSource.swift` | Protocol + tipos normalizados + errores |
| `Core/Music/AppleMusicSource.swift` | Adaptador MusicKit (MVP) |
| `Core/Music/SpotifySource.swift` | Adaptador OAuth (V2) |
| `Core/Music/HypeEngine.swift` | Score + energía + personality (reglas) |
| `Models/MusicPassport.swift` | Modelo + `MusicProfileStore` (@MainActor, persistido) |
| `Features/Tonight/HypeWeekCard.swift` | "Your Hype This Week 🔥" + connect flow |
| `Features/Profile/MusicPassportView.swift` | Passport visual compartible |
| `NightPlanner.swift` (extender) | señal `musicMatch` en el scoring |

---

## 4. Flujo de usuario

```
1. BIENVENIDA (Tonight, primera vez)
   Card: "🎵 Conectá tu música — descubrí a dónde salir según lo que escuchás"
   [Conectar Apple Music]  →  permiso del sistema (MusicKit)

2. PERMISO OK → snapshot on-device → HypeEngine → Passport guardado
   La card se transforma en "Your Hype This Week 🔥":
   · "Tu semana fue 84% High Energy"
   · géneros + 3 artistas top + descubrimientos

3. EFECTO EN TODA LA APP (automático)
   · Venue cards y detalle: badge "🎵 match 87%"
   · "Armá mi noche": el matching musical sube venues compatibles
   · Perfil: Music Passport (night personality, energía, screenshot-friendly)

4. SIN CONEXIÓN / SIN PERMISO
   La capa no existe. Cero placeholders, cero datos fake.

5. V2: Tastemakers
   Marcar artista temprano → XP/misiones (PointsEngine ya existente)
```

**Night Personality (reglas v1, transparentes):**
energía>75 + club/EDM dominante → "Night Explorer" · latin dominante →
"Ritmo Local" · jazz/lounge → "After Dark Curator" · diversidad>0.8 →
"Genre Hopper" · default → "Nightlifer".

---

## 5. Roadmap

### MVP (Fase 1)
- [x] Este documento
- [ ] `MusicSource` protocol + tipos
- [ ] `AppleMusicSource` (MusicKit) + permission flow + Info.plist
- [ ] `HypeEngine` + `MusicPassport` + store persistido
- [ ] `HypeWeekCard` en Tonight (connect → hype)
- [ ] Match badges + señal en NightPlanner
- [ ] Passport en Perfil
- ⚠️ **Dependencia externa:** cuenta Apple Developer ($99) con MusicKit
  habilitado para el bundle id. El código queda gated con estados honestos
  (`.notEntitled` → la card explica qué falta) hasta que exista.

### V2
- [ ] SpotifySource (OAuth top-items) + merge multi-proveedor
- [ ] Tabla `music_passports` en Supabase (opt-in público)
- [ ] Tastemakers → XP/misiones
- [ ] Tabla `artists` + `artist_snapshots` (momentum = Δ propio, honesto)

### V3
- [ ] Perfiles de artista self-service + Rising Artists
- [ ] Marketplace venue↔artista (requiere ambos lados con masa crítica)
- [ ] Previews de audio (Apple Music embeds 30s) en perfiles de artista
- [ ] "Personas con tu vibra" (matching social sobre passports públicos)

### Descartado (honesto)
- Feed TikTok con reproducción completa: licencias musicales fuera de alcance.
- Métricas de crecimiento de artistas de terceros: data privada de las
  plataformas; solo momentum derivado de snapshots propios.

---

## 6. Integración sin romper nada

- Todo es **aditivo**: protocol nuevo, archivos nuevos, tablas nuevas.
- `NightPlanner.plan()` gana una señal opcional (default = sin efecto).
- La UI nueva es condicional a `MusicProfileStore.hasPassport`.
- Sin música conectada, la app es bit a bit la de hoy.

## 7. Ventaja competitiva

1. **El grafo escucha↔asistencia** — check-ins GPS reales × perfil musical.
   Se acumula cada viernes y nadie más lo tiene.
2. **On-device privacy** — "tu música nunca sale de tu teléfono" es una
   afirmación verificable que Spotify/Meta no pueden hacer.
3. **Multi-proveedor desde el día 1** — no somos rehenes de la API de nadie;
   deprecar un endpoint de Spotify no mata la feature.
4. **Del descubrimiento a la puerta del club** — el loop completo
   (escuchás → match → Armá mi noche → Priority Entry) vive en una sola app.
