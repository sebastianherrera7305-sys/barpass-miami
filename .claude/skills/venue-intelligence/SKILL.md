---
name: venue-intelligence
description: El motor que llena lo que BarPass sabe de cada venue por dentro — cuánto sale un trago y cuál pedir, cuántas barras hay adentro y dónde está el baño, qué música ponen, qué edad hay, cuánta gente entra, cómo es la puerta. Define de dónde sale cada campo, cómo se verifica, cómo se escribe con procedencia, cuándo se deja vacío, y qué sólo puede contestar alguien que está adentro. Usar al enriquecer venues, al agregar un campo nuevo al catálogo, al decidir si un dato puede mostrarse, o al construir cualquier pantalla que prometa saber algo de un lugar.
---

# Venue Intelligence

## Qué estamos construyendo, y contra qué

Google te dice que el lugar existe, dónde queda y a qué hora abre. Eso ya está
resuelto y no es un negocio.

Lo que nadie te dice antes de entrar: cuánto te va a salir un trago, qué se pide
ahí, si hay una sola barra o cuatro, dónde está el baño, qué música van a poner
un jueves, qué edad hay adentro, si vale la pena la fila a las 12 o a la 1.
Eso es lo que sabe un regular del lugar. **Ese es el producto.** Cada campo de
este motor existe para contestar una pregunta que alguien se hace parado en la
vereda, con el teléfono en la mano, decidiendo si entra.

Si un campo no contesta ninguna pregunta de esas, no va.

## La regla que no se rompe

**Un valor vacío es un hecho. Un valor inventado es una mentira que sobrevive
meses porque nada la marca como inventada.**

Esta regla no es teórica; el catálogo ya la rompió tres veces:

1. `music_genres` tenía `['hip_hop','house']` idéntico en 175 filas, incluidos
   bares deportivos y una cervecería. Origen probable: la copia publicitaria de
   un promotor describiendo *otros* clubes. Se limpió una por una contra
   fuentes primarias.
2. `crowd_level` dice `steady` en **el 100%** de las 4.264 filas. Es un default
   sembrado, no una medición. Por eso la barra de "Crowd" ya no se dibuja en
   iOS — pero el dato sigue en la base y hay que vaciarlo, no maquillarlo.
3. `popular_drinks` guarda `"[]"` (un array vacío serializado como string) en
   miles de filas. Contado ingenuamente da **63% de cobertura**; mirando
   adentro, la cobertura real es **4%**. Un vacío disfrazado de dato es peor
   que un NULL, porque hasta tus propias métricas te mienten.

Antes de reportar cobertura de cualquier campo: **abrí el valor**. `not.is.null`
no alcanza.

## Estado real al 16-sep-2026 (4.264 venues servibles)

| Campo | Cobertura real | Nota |
|---|---|---|
| `hours` (semanal) | 86% | Google Places, confiable |
| `website` / `phone` | 89% / 87% | materia prima para todo lo demás |
| `price_tier` | 80% | Google, escala $ |
| `restroom` / `good_for_groups` | 91% / 83% | amenities de Google, booleanos |
| `age_policy` | 59% | |
| `music_genres` | 19% | bajo **a propósito** tras la purga |
| **`popular_drinks` con precio** | **4%** (188 de 3.076 de salir) | el campo más valioso, casi vacío |
| `dress_code`, `parking`, `peak_hours`, `best_arrival_time`, `avg_spend`, `cover_men/women`, `vibes` | **0%** | columnas existentes, nunca llenadas |
| cuántas barras adentro, dónde el baño, capacidad | no existe la tabla | ver escalera C |

## Las tres escaleras de fuente

Cada campo sale de una sola escalera. Saber cuál es decide si el dato se puede
conseguir masivamente o no — y confundirlas es lo que hace que un plan de
"llenamos todo en tres días" fracase.

### A · Público y verificable (se puede correr en lote)

Google Places, el sitio del venue, su carta en PDF/HTML, el portal de licencias
de alcohol del condado, Ticketmaster para los lugares de concierto.

Sirve para: horarios, teléfono, web, amenities, tipo, nivel de precio, carta y
precios de tragos, política de edad publicada, dress code publicado, noches
fijas publicadas (trivia martes, ladies night jueves).

**Trampa medida:** los sitios de bares hoy son Squarespace/Wix. Kin (Gainesville)
devuelve 85 KB de HTML y **1.374 caracteres de texto**; Capone's, 1 MB de HTML y
**659 caracteres**. Un `fetch` + regex no ve nada. Hay que renderizar la página
como un navegador y recién ahí extraer. Presupuestá eso o el lote falla en
silencio con "no encontré nada".

### B · Derivable de lo que ya tenemos (gratis, sólo código)

De `hours` sale "abre tarde" y "cierra 2 AM" → señal de salir, no de cenar.
De `type` + alcohol + cierre pasada la medianoche sale la clasificación de
nightlife (la regla que rescató los bares de college: **sirve alcohol Y cierra
pasada la medianoche = bar**, sin importar la etiqueta de Google).
De `venue_checkins` sale el pulso real por hora y por día.
De `venue_media` sale qué tan viva está la noche ahora mismo.

Derivar es siempre mejor que pedir: no gasta cuota de API y no puede mentir más
de lo que ya mienten sus insumos.

### C · Sólo lo sabe quien está adentro (y acá está el foso)

Cuánto pagaste realmente por un trago (la carta dice $14, el jueves de
estudiantes sale $6). Cuántas barras hay. Dónde está el baño. Cuánto esperaste
en la fila. Qué edad había. Qué tan lleno estaba a la 1 AM. Si el DJ era bueno.

**Google no puede tener esto nunca, porque no tiene a nadie adentro. Nosotros
sí: tenemos check-ins.** Esta escalera no se raspa, se cosecha, y es la única
parte del producto que no se puede copiar con un scraper.

La app ya tiene las piezas: `AgeReportSheet` y el reporte de precio se
presentan en el check-out — el único momento en que sabemos con certeza que la
persona estuvo adentro. `venue_age_effective` ya separa "investigado" de
"reportado", que es la distinción correcta: no son la misma afirmación y no se
muestran igual.

**Reglas de la cosecha:**
- Una sola pregunta por noche por persona. Dos es un formulario, y un formulario
  a la salida de un bar no lo contesta nadie.
- La pregunta se elige por lo que le falta a ESE venue, no al azar.
- Un reporte solo no es un dato: se muestra como "reportado" hasta que
  N reportes concuerden (mediana, no promedio — un borracho tipeando $200 no
  puede mover el número).
- Nunca se pregunta nada que la persona no pueda saber con certeza.
- Se guarda quién reportó para poder descartar abusos, pero **nunca** se muestra
  ni se devuelve por la API: ese es el historial de ubicación que ya cerramos a
  nivel columna en `venue_media`.

## Campo por campo

| Campo | Escalera | Fuente concreta | Cuándo queda NULL |
|---|---|---|---|
| `popular_drinks` (nombre + precio) | A, después C | carta del venue (HTML/PDF renderizado); el precio real lo corrige el reporte de check-out | si no hay carta pública: NULL, y el reporte de precio pasa a ser la pregunta prioritaria de ese venue |
| `avg_spend` | C | mediana de reportes de precio × 2-3 tragos + cover | siempre NULL hasta tener ≥3 reportes. **Nunca** estimar desde `price_tier` |
| `cover_men` / `cover_women` | A + C | web del venue; reporte de puerta | NULL. Un cover inventado hace que alguien vaya con la plata justa y no entre |
| `music_genres` | A | sitio, line-up, IG del venue, prensa local | NULL si ninguna fuente lo dice. 14 géneros; `live` es formato, no género, y compone (`[country, live]`) |
| `age_policy` / brackets | A (lo publicado) + C (lo real) | web/puerta para la política; `venue_age_reports` para la realidad | separados siempre: "21+" es la regla, "22-26" es quién va |
| `dress_code` | A | web del venue | NULL si no está publicado. Es de los que más duele inventar |
| `peak_hours`, `best_arrival_time` | B | curva de `venue_checkins` por hora | NULL hasta tener volumen real en ese venue |
| `crowd_level` | B | check-ins de la última hora vs. su propia mediana | **vaciar el `steady` sembrado**; mostrar sólo donde haya check-ins |
| barras adentro, baños, zonas | C | foto del mapa de entrada + reportes | no existe todavía; ver "Lo que falta construir" |
| capacidad | A | licencia de ocupación del condado (es público en la mayoría de los estados) | NULL |
| noches fijas (trivia, ladies night) | A | web renderizada del venue | NULL; no confundir con evento único |

## Cómo se escribe

- **Siempre por `id`, nunca por nombre.** Los nombres se repiten entre ciudades
  y dentro de una. Actualizar por `name=eq.…` ya excluyó mal tres Miller's Ale
  House y el Kilroy's de Bloomington.
- **Procedencia obligatoria** en `field_sources`, que ya tiene la forma correcta:
  `{"music_genres": {"source": "manual_research", "at": "2026-09-01", "confidence": "high"}}`.
  Un campo sin procedencia es un campo que nadie va a poder auditar en tres meses.
- **PostgREST corta en 1.000 filas.** Todo lote lee paginando con `Range`. Un
  script ya reportó "listo, 3.919 venues" habiendo tocado 999.
- **Reintentar con backoff.** Un corte de red mató una corrida de 3.900 llamadas.
- **Verificar contra la base después de correr, no contra el exit code.** Un
  pipe a `grep` sale 0 aunque todo haya fallado.

## Cómo correr un lote

1. `--dry-run` primero, siempre, e imprimir qué se va a escribir por venue.
2. Una ciudad de prueba antes de las 23. Elegir una donde puedas verificar a
   mano: Gainesville o Miami.
3. Contar después: cuántos quedaron con dato, cuántos NULL, y **abrir tres al
   azar** para ver que el dato sea verdad y no basura bien formateada.
4. Recién ahí, el resto.

## Lo que falta construir (en orden de valor)

1. **Extractor de cartas con render.** Es el campo más valioso (4% hoy) y el que
   contesta la pregunta que más se hace la gente. Sin render no hay carta.
2. **La pregunta correcta al check-out.** Ya existe el momento y la cola offline;
   falta elegir la pregunta según lo que le falta a ese venue.
3. **"Adentro": barras, baños, zonas.** Empezar por la foto del mapa de entrada
   que ya se puede subir, más una pregunta de una sola respuesta ("¿cuántas
   barras había?"). No hace falta un plano.
4. **Pulso real** desde check-ins, para matar el `crowd_level` sembrado.
5. **Capacidad** desde licencias de ocupación del condado: es público, es exacto,
   y nadie lo está usando.

## Qué no hacer

- No estimar un precio desde `price_tier`. "$$" no es un número.
- No traducir un dato del venue con el modelo: si la carta dice "Well drink",
  se guarda "Well drink".
- No rellenar un campo vacío para que la pantalla se vea completa. La pantalla
  tiene que saber verse bien con el campo vacío — eso es trabajo de UI, no
  excusa para inventar.
- No mezclar lo publicado con lo reportado en el mismo campo. Son dos
  afirmaciones distintas y el usuario merece saber cuál está leyendo.
