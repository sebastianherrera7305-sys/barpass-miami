# BarPass Onboarding — Brief de las 6 escenas de video

> Brief de producción para los clips que faltan en `OnboardingVideoView.swift`.
> Última actualización: 2026-09-01.
> Objetivo: **que el usuario llegue al login ya queriendo entrar, no evaluando si vale la pena.**

---

## 0. Por qué existe este documento

`Features/Onboarding/OnboardingVideoView.swift` ya está construido y funciona:
maneja 6 escenas, transiciones, captions, skip, indicador de progreso y
accesibilidad. Lo único que le falta son **los 6 archivos `.mp4`**. Sin ellos
el view detecta que no hay video y llama a `finish()` de inmediato — el
onboarding se salta solo.

Este documento es el brief para generar esos 6 clips. No propone cambios de
código: la estructura de escenas, los tiempos y las captions ya existen.

### Restricciones que definen el brief

Tres hechos del sistema que condicionan todo lo que estos videos pueden hacer:

1. **Corre antes del login.** No hay usuario, ni nombre, ni ciudad, ni
   preferencias. Nada personalizable. La ciudad se pide después, en
   `CityPickerView`. Esto descarta cualquier idea de "tu noche, {nombre}".
2. **Es saltable en todo momento.** Hay un botón *Saltar* fijo arriba a la
   derecha, y un tap avanza de escena. El video compite contra el pulgar del
   usuario en cada segundo.
3. **Duración total ~30s** (6 escenas × 5s por defecto en `SceneInfo.duration`).
   Casi nadie llega al final. **La escena 1 y la 2 cargan el peso real.**

Corolario de diseño: esto **no** es un tutorial. No explica cómo funciona la
app. Vende una sensación y devuelve el control rápido.

---

## 1. Las 6 escenas

Las captions ya viven en `LocalizationService.swift` bajo `onboarding.caption.N`
(ES/EN/PT). Las escenas 1 y 4 son deliberadamente **sin texto** — respiran y
dejan que la imagen hable.

| # | Caption (ES) | Rol narrativo |
|---|---|---|
| 1 | *(sin texto)* | Gancho. Miami de noche, reconocible en 1 segundo. |
| 2 | Desde el juego hasta la fiesta | Amplitud: no es solo clubs. |
| 3 | Festivales. Cultura. Energía. | Amplitud II: la ciudad entera. |
| 4 | *(sin texto)* | Respiro emocional. Gente, no lugares. |
| 5 | Los mejores clubs. Tu acceso. | **La promesa.** Acá aparece el producto. |
| 6 | Un toque. Adentro. | Cierre: fricción cero → corta al login. |

### Escena 1 — El gancho (sin caption)

Aérea nocturna de Miami bajando hacia South Beach: palmeras, neón art déco,
el océano a la izquierda. Movimiento continuo hacia adelante, nunca estático.

- **Por qué:** identificación geográfica instantánea. El usuario debe pensar
  "esto es Miami" antes de leer una sola palabra.
- **Sin texto a propósito:** compite con el impulso de saltar; una imagen
  fuerte retiene mejor que una frase en el segundo 1.

### Escena 2 — Desde el juego hasta la fiesta

Corte de estadio lleno (luces, multitud de pie) a un rooftop bar de noche.
La transición es el mensaje: **una noche, dos mundos.**

- **Por qué:** rompe la suposición de "esto es solo para gente de club". El
  repo ya tiene integración con Hard Rock Stadium (`barpass-map.html`) — la
  escena refleja producto real, no aspiración.

### Escena 3 — Festivales. Cultura. Energía.

Festival al aire libre: escenario, luces, manos arriba, confeti. Wynwood
como referencia visual (murales, color saturado).

- **Por qué:** completa el mapa mental — la app cubre la vida nocturna
  entera, no un nicho.

### Escena 4 — El respiro (sin caption)

Primeros planos de **gente**, no de lugares: un grupo riéndose, un brindis,
alguien bailando. Cámara lenta, cálida, granulada.

- **Por qué:** las tres escenas anteriores son espectáculo. Esta es
  pertenencia. El producto no vende venues, vende con quién los vivís.
- **Sin texto a propósito:** el silencio hace el contraste emocional.

### Escena 5 — Los mejores clubs. Tu acceso.

Un club premium desde adentro. Punto clave: **el POV pasa la fila**, no la
hace. Se ve la puerta abrirse desde adelante, no la espera desde atrás.

- **Por qué:** es la única escena que promete algo concreto. "Tu acceso"
  debe leerse como estatus, no como suscripción. Es el pico emocional.

### Escena 6 — Un toque. Adentro.

Cierre corto y seco: un teléfono se acerca a un lector, luz verde, la
persona entra. Sin fricción visible.

- **Por qué:** cierra el bucle con el producto real — los pases QR ya
  existen (`/api/passes`, `credential.html`, `validate`). Termina en
  movimiento, y corta directo al login mientras dura el impulso.

---

## 2. Dirección de arte

Consistencia visual con la marca ya definida en la app:

- **Paleta:** negro profundo dominante, ámbar de marca como acento
  (`--color-amber-brand: #ebb847`), neón magenta/púrpura solo como luz
  ambiente. Nunca lavado ni pastel.
- **Cámara:** siempre en movimiento — dolly, drone, handheld suave. Ningún
  plano fijo. La app es sobre salir, la cámara no se queda quieta.
- **Gente:** presente pero sin protagonista identificable. Nadie debe
  parecer "el actor del comercial"; se busca sensación de estar ahí.
- **Diversidad real de Miami:** latino, negro, blanco, mezclado. No es
  casting inclusivo por cuota — es cómo se ve la ciudad de verdad.
- **Sin texto quemado en el video.** Las captions las dibuja SwiftUI encima,
  y están traducidas a ES/EN/PT. Texto dentro del `.mp4` rompería la
  localización.
- **Sin logos de venues reales** salvo que exista permiso escrito. Riesgo
  legal innecesario en la primera pantalla de la app.

---

## 3. Especificaciones técnicas

Definidas por cómo `OnboardingVideoView` los consume:

| Parámetro | Valor | Razón |
|---|---|---|
| Nombres | `scene1.mp4` … `scene6.mp4` | `SceneInfo.file` los busca literal |
| Ubicación | carpeta `Onboarding/` del bundle | `Bundle.main.url(..., subdirectory: "Onboarding")` |
| Formato | H.264 / HEVC en `.mp4` | AVPlayer nativo |
| Orientación | **Vertical 9:16** | `videoGravity = .resizeAspectFill` recorta horizontales |
| Resolución | 1080×1920 | suficiente; 4K infla el binario sin ganancia visible |
| Duración | 5s por clip | coincide con `SceneInfo.duration = 5.0` |
| Audio | **ninguno / pista muda** | el player fuerza `isMuted = true` |
| Peso objetivo | ≤ 3 MB por clip | 6 clips ≈ 18 MB del tamaño de descarga |

> **Importante sobre el peso:** estos 6 archivos van dentro del binario y
> afectan el tamaño de descarga en App Store, que es fricción de instalación
> medible. Si los clips superan ~3 MB cada uno, conviene evaluar bajar
> bitrate antes que resolución.

### Cómo probarlos

1. Arrastrar los 6 `.mp4` a una carpeta `Onboarding` dentro del target.
2. Confirmar que quedan en *Copy Bundle Resources* (no solo referenciados).
3. Correr la app con la sesión cerrada. Si el onboarding se salta solo, el
   bundle no los encontró — el fallback de `hasAnyVideo` está haciendo su
   trabajo.
4. Probar en los tres idiomas (Perfil → idioma) para verificar las captions.

---

## 4. Pendientes / decisiones abiertas

- **Generación:** los clips estaban planeados con Higgsfield. Cualquier
  generador sirve mientras respete 9:16 y la dirección de arte de §2.
- **Derechos de imagen:** si los clips son generados por IA, confirmar que la
  licencia del proveedor permite uso comercial en una app publicada.
- **Escena 5 y venues reales:** decidir si se filma/genera un club genérico o
  se negocia con un venue asociado. Hoy el brief asume genérico.
- **Sin métricas de retención:** no hay evento analítico en el onboarding —
  no se sabe en qué escena la gente saltea. Si importa optimizarlo después,
  hay que instrumentar `advanceScene()` y el botón *Saltar* primero.
