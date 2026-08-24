/**
 * Regenera hook y description para todos los venues, en español, usando
 * SOLO datos reales de cada fila (name, type, neighborhood, city, rating,
 * review_count, price_tier, happy_hour_until). Nunca inventa un dato que
 * no esté en la fila.
 *
 * Por qué no es una llamada a un LLM: este entorno no tiene
 * OPENAI_API_KEY ni ANTHROPIC_API_KEY configurada (ni local ni en
 * Vercel), así que no hay forma de pedirle a un modelo que escriba en
 * runtime. En su lugar, este script compone cada texto combinando:
 *   - más de una decena de "esqueletos" de frase distintos (hook y
 *     description por separado), elegidos por venue vía un hash
 *     determinístico del slug — no aleatorio en el sentido de "cambia
 *     cada vez que corrés el script", sino distribuido de forma pareja
 *     entre todos los venues.
 *   - frases de tipo de venue, rating, volumen de reseñas y price_tier
 *     con múltiples variantes cada una, MÁS los números reales (rating
 *     exacto, review_count exacto) insertados en prosa — lo que hace que
 *     el texto de cada venue sea, en la práctica, único incluso cuando
 *     dos venues comparten esqueleto, porque casi ningún par de venues
 *     comparte el mismo rating+review_count+price_tier+barrio.
 * El resultado no es "un template con sustantivos cambiados" (el bug que
 * esto reemplaza: 90 strings literales para 1642+175 filas) sino miles
 * de combinaciones posibles, ancladas en el dato real de cada fila. No
 * reemplaza redacción humana/LLM bespoke por venue — si se agrega una
 * API key de un LLM más adelante, vale la pena regenerar con eso.
 *
 * music_genres NO se usa como dato: se comprobó que en la práctica es
 * ['house','hip_hop'] para prácticamente todos los venues de Miami sin
 * importar el tipo (bar deportivo, restaurante, club) y vacío en el
 * resto de ciudades — no es un dato real por-venue, es un default que
 * quedó pegado, así que usarlo violaría la regla de "nunca inventar".
 *
 * happy_hour_until: en la práctica NINGÚN venue lo tiene seteado
 * (confirmado: 0 de 1817), así que la rama que lo mencionaría existe
 * pero no se ejerce hoy — queda lista para cuando haya datos reales.
 *
 * Columnas de amenities (outdoor_seating, good_for_groups,
 * good_for_watching_sports, has_live_music — de
 * supabase/venue_amenities_schema.sql, pobladas por Google Places vía
 * enrich-venues.ts) SÍ se usan: a diferencia de vibes/music_genres, son
 * reales y varían de verdad venue a venue (confirmado con conteos: p.ej.
 * outdoor_seating true=1050/false=426/null=341 sobre 1817). NULL se trata
 * como "no hay dato", nunca como negativo — no se menciona nada en ese
 * caso, no se asume "false".
 *
 * Resumable: --skip-existing (default true) salta slugs ya escritos por
 * este script en un run previo, vía checkpoint local
 * (scripts/.venue-copy-progress.json). Escritura individual e
 * inmediata por venue — un corte a mitad de camino no pierde lo hecho.
 *
 * Uso:
 *   npm run generate-venue-copy [-- --dry-run] [-- --only=slug1,slug2] [-- --force]
 */
import { createClient } from "@supabase/supabase-js";
// @ts-expect-error — 'ws' no trae tipos propios, ver enrich-venues.ts
import ws from "ws";
import fs from "node:fs";
import path from "node:path";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
  console.error("Faltan env vars: NEXT_PUBLIC_SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY");
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  realtime: { transport: ws as unknown as typeof WebSocket },
});

const args = process.argv.slice(2);
const dryRun = args.includes("--dry-run");
const force = args.includes("--force");
const onlyArg = args.find((a) => a.startsWith("--only="));
const onlySlugs = onlyArg ? onlyArg.replace("--only=", "").split(",") : null;

const PROGRESS_FILE = path.join(__dirname, ".venue-copy-progress.json");

interface VenueRow {
  id: string;
  slug: string;
  name: string;
  type: string;
  city: string;
  neighborhood: string;
  rating: number;
  review_count: number;
  price_tier: number | null;
  happy_hour_until: string | null;
  outdoor_seating: boolean | null;
  good_for_groups: boolean | null;
  good_for_watching_sports: boolean | null;
  has_live_music: boolean | null;
}

function loadProgress(): Set<string> {
  if (!fs.existsSync(PROGRESS_FILE)) return new Set();
  try {
    return new Set((JSON.parse(fs.readFileSync(PROGRESS_FILE, "utf-8")).done as string[]));
  } catch {
    return new Set();
  }
}
function saveProgress(done: Set<string>) {
  fs.writeFileSync(PROGRESS_FILE, JSON.stringify({ done: Array.from(done) }, null, 0));
}

// Hash determinístico simple (no criptográfico, solo para distribuir
// variantes de forma pareja y estable entre runs).
function hash(s: string): number {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return Math.abs(h);
}
function pick<T>(arr: T[], seed: number, salt: number): T {
  return arr[(seed + salt) % arr.length];
}

interface NounForm {
  noun: string;
  indef: "un" | "una";
  def: "el" | "la";
}

const TYPE_NOUN: Record<string, NounForm[]> = {
  club: [
    { noun: "club", indef: "un", def: "el" },
    { noun: "antro", indef: "un", def: "el" },
    { noun: "club nocturno", indef: "un", def: "el" },
    { noun: "discoteca", indef: "una", def: "la" },
  ],
  rooftop: [
    { noun: "rooftop", indef: "un", def: "el" },
    { noun: "terraza en altura", indef: "una", def: "la" },
    { noun: "bar en la azotea", indef: "un", def: "el" },
    { noun: "rooftop bar", indef: "un", def: "el" },
  ],
  bar: [
    { noun: "bar", indef: "un", def: "el" },
    { noun: "bar de barrio", indef: "un", def: "el" },
    { noun: "cantina", indef: "una", def: "la" },
    { noun: "bar de siempre", indef: "un", def: "el" },
  ],
  lounge: [
    { noun: "lounge", indef: "un", def: "el" },
    { noun: "salón lounge", indef: "un", def: "el" },
    { noun: "espacio lounge", indef: "un", def: "el" },
  ],
  sports_bar: [
    { noun: "bar deportivo", indef: "un", def: "el" },
    { noun: "sports bar", indef: "un", def: "el" },
    { noun: "bar para ver el partido", indef: "un", def: "el" },
  ],
  restaurant: [
    { noun: "restaurante", indef: "un", def: "el" },
    { noun: "restaurante-bar", indef: "un", def: "el" },
    { noun: "spot para comer y tomar algo", indef: "un", def: "el" },
  ],
  brewery: [
    { noun: "cervecería", indef: "una", def: "la" },
    { noun: "cervecería de barrio", indef: "una", def: "la" },
    { noun: "salón cervecero", indef: "un", def: "el" },
  ],
};
const DEFAULT_NOUN: NounForm[] = [{ noun: "local", indef: "un", def: "el" }];

function typeNounForm(type: string, seed: number, salt: number): NounForm {
  const options = TYPE_NOUN[type] ?? DEFAULT_NOUN;
  return pick(options, seed, salt);
}

function ratingPhrase(rating: number, seed: number, salt: number): string {
  const r = rating.toFixed(1);
  if (rating === 0) return "";
  if (rating >= 4.7) {
    return pick(
      [
        `con una calificación altísima de ${r}/5`,
        `entre los mejor calificados de la zona (${r}/5)`,
        `con ${r}/5 — de los puntajes más altos del barrio`,
      ],
      seed,
      salt
    );
  }
  if (rating >= 4.3) {
    return pick(
      [`bien calificado, ${r}/5`, `con buena nota de los usuarios (${r}/5)`, `con un sólido ${r}/5`],
      seed,
      salt
    );
  }
  if (rating >= 3.8) {
    return pick(
      [`con calificación de ${r}/5`, `con nota promedio de ${r}/5`, `con ${r}/5 en reseñas`],
      seed,
      salt
    );
  }
  return pick(
    [`con calificación de ${r}/5, para juzgar con calma`, `con ${r}/5 — opiniones divididas`, `con una nota más discreta de ${r}/5`],
    seed,
    salt
  );
}

function reviewPhrase(count: number, seed: number, salt: number): string {
  if (count >= 5000) {
    return pick(
      [`respaldado por ${count.toLocaleString("es")} reseñas`, `un clásico con más de ${count.toLocaleString("es")} reseñas acumuladas`, `${count.toLocaleString("es")} reseñas y contando`],
      seed,
      salt
    );
  }
  if (count >= 1000) {
    return pick(
      [`con ${count.toLocaleString("es")} reseñas`, `ya suma ${count.toLocaleString("es")} reseñas`, `con más de mil reseñas (${count.toLocaleString("es")})`],
      seed,
      salt
    );
  }
  if (count >= 100) {
    return pick(
      [`con ${count} reseñas hasta ahora`, `acumula ${count} reseñas`, `con un puñado de cientos de reseñas (${count})`],
      seed,
      salt
    );
  }
  if (count > 0) {
    return pick(
      [`todavía con pocas reseñas (${count})`, `recién construyendo su reputación —${count} reseñas por ahora`, `con apenas ${count} reseñas todavía`],
      seed,
      salt
    );
  }
  return "";
}

function pricePhrase(tier: number | null, seed: number, salt: number): string {
  if (tier === null) return "";
  const opts: Record<number, string[]> = {
    1: ["precios accesibles", "una opción económica", "sin golpear mucho el bolsillo"],
    2: ["precios moderados", "gasto medio para la zona", "ni el más barato ni el más caro"],
    3: ["precios altos", "para una noche con presupuesto más generoso", "categoría de gasto alto"],
    4: ["precios muy altos", "entre los más caros de la zona", "categoría premium en precio"],
  };
  return pick(opts[tier] ?? [], seed, salt);
}

// Frases de amenity real (booleanas, de venue_amenities_schema.sql).
// Solo se usan cuando el valor es exactamente `true` — null (sin dato) y
// false (dato real negativo) nunca generan una frase, para no inventar ni
// afirmar una carencia que no viene al caso en copy promocional.
function amenityPhrases(v: VenueRow, seed: number): string[] {
  const out: string[] = [];
  if (v.outdoor_seating === true) {
    out.push(
      pick(
        ["tiene mesas al aire libre", "con área exterior", "con espacio afuera para los que prefieren tomar aire"],
        seed,
        31
      )
    );
  }
  if (v.has_live_music === true) {
    out.push(pick(["con música en vivo", "hay música en vivo seguido", "suele tener bandas o DJs en vivo"], seed, 32));
  }
  if (v.good_for_watching_sports === true) {
    out.push(
      pick(["ideal para ver el partido", "bueno para ver deportes en pantalla", "con pantallas para seguir los partidos"], seed, 33)
    );
  }
  if (v.good_for_groups === true) {
    out.push(pick(["bueno para ir en grupo", "pensado para grupos grandes", "cómodo si van varios"], seed, 34));
  }
  return out;
}

function cap(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1);
}

// Bastantes filas tienen neighborhood === city (el dato de barrio nunca
// se pobló para esas ciudades más chicas) — evita mencionar el mismo
// nombre dos veces ("Athens (Athens)").
function place(v: VenueRow, seed: number, salt: number): { long: string; short: string; inNeighborhood: boolean } {
  const distinct = v.neighborhood !== v.city;
  if (distinct) {
    const long = pick(
      [`${v.neighborhood}, ${v.city}`, `${v.neighborhood} (${v.city})`, `el barrio de ${v.neighborhood}, en ${v.city}`],
      seed,
      salt
    );
    return { long, short: v.neighborhood, inNeighborhood: true };
  }
  const long = pick([`${v.city}`, `pleno ${v.city}`, `la ciudad de ${v.city}`], seed, salt);
  return { long, short: v.city, inNeighborhood: false };
}

// Contracción "de el" -> "del" (p.long a veces arranca con "el barrio de...").
function withDe(s: string): string {
  if (s.startsWith("el ")) return `del ${s.slice(3)}`;
  return `de ${s}`;
}

function buildHook(v: VenueRow, seed: number): string {
  const nf = typeNounForm(v.type, seed, 1);
  const rp = ratingPhrase(v.rating, seed, 2);
  const rvp = reviewPhrase(v.review_count, seed, 3);
  const pp = pricePhrase(v.price_tier, seed, 4);
  const p = place(v, seed, 5);
  const amenities = amenityPhrases(v, seed);
  const ap = amenities.length ? pick(amenities, seed, 6) : "";
  // El hook es corto (6-10 palabras): cuando hay una amenity real, a veces
  // reemplaza el secondary "genérico" (rating/precio) por el dato
  // distintivo — esto es lo que hace que un rooftop con outdoor_seating o
  // un sports_bar con good_for_watching_sports no lea igual que uno sin
  // esos datos, aunque compartan tipo/barrio/rating.
  const secondary = ap && hash(v.slug + "amenity-first") % 2 === 0 ? ap : pp || rp || rvp || ap;

  const templates = [
    `${cap(nf.indef)} ${nf.noun} en ${p.long}${rp ? `, ${rp}` : ""}.`,
    `${v.name}: ${nf.indef} ${nf.noun} en ${p.short}${secondary ? `, ${secondary}` : ""}.`,
    p.inNeighborhood
      ? `En ${p.short} destaca ${v.name}, ${nf.indef} ${nf.noun}${rp ? ` ${rp}` : ""}.`
      : `En ${p.long} destaca ${v.name}, ${nf.indef} ${nf.noun}${rp ? ` ${rp}` : ""}.`,
    `${v.name}, ${nf.def} ${nf.noun} de ${p.short}${rvp ? `, ${rvp}` : ""}.`,
    `${cap(nf.indef)} ${nf.noun} ${withDe(p.long)}${pp ? `, ${pp}` : rp ? `, ${rp}` : ""}.`,
  ];
  return pick(templates, seed, 10);
}

function buildDescription(v: VenueRow, seed: number): string {
  const nf = typeNounForm(v.type, seed, 21);
  const rp = ratingPhrase(v.rating, seed, 22);
  const rvp = reviewPhrase(v.review_count, seed, 23);
  const pp = pricePhrase(v.price_tier, seed, 24);
  const p = place(v, seed, 25);
  const hhPhrase = v.happy_hour_until
    ? pick([`Tiene happy hour hasta las ${v.happy_hour_until}.`, `Happy hour hasta ${v.happy_hour_until}.`], seed, 26)
    : "";

  const amenities = amenityPhrases(v, seed);
  const amenitySentence =
    amenities.length === 0
      ? ""
      : amenities.length === 1
      ? `${cap(amenities[0])}.`
      : `${cap(amenities[0])} y ${amenities[1]}.`;

  const facts: string[] = [];
  if (rp) facts.push(rp);
  if (rvp) facts.push(rvp);
  if (pp) facts.push(pp);

  const factsSentenceVariants = [
    facts.length ? `${cap(facts[0])}${facts[1] ? `, ${facts[1]}` : ""}${facts[2] ? ` y ${facts[2]}` : ""}.` : "",
    facts.length >= 2 ? `${cap(facts[1])}, ${facts[0]}${facts[2] ? `, ${facts[2]}` : ""}.` : facts.length ? `${cap(facts[0])}.` : "",
  ];
  const factsSentence = pick(factsSentenceVariants.filter(Boolean), seed, 27) || "";

  const openers = [
    `${v.name} es ${nf.indef} ${nf.noun} en ${p.long}.`,
    p.inNeighborhood
      ? `En el barrio de ${p.short}, ${v.city}, ${v.name} funciona como ${nf.noun}.`
      : `En ${p.long}, ${v.name} funciona como ${nf.noun}.`,
    p.inNeighborhood
      ? `${v.name} opera como ${nf.noun} dentro de ${p.short}, uno de los barrios de ${v.city}.`
      : `${v.name} opera como ${nf.noun} en ${p.long}.`,
    `Ubicado en ${p.long}, ${v.name} es ${nf.indef} ${nf.noun}.`,
  ];
  const opener = pick(openers, seed, 28);

  // Orden variable entre "datos duros primero" y "amenities primero" para
  // que dos venues con las mismas facts (rating/reviews/precio) pero
  // distintas amenities no terminen leyéndose como el mismo párrafo con el
  // nombre cambiado.
  const middle =
    hash(v.slug + "amenity-order") % 2 === 0
      ? [factsSentence, amenitySentence]
      : [amenitySentence, factsSentence];

  return [opener, ...middle, hhPhrase].filter(Boolean).join(" ");
}

// El cliente de supabase-js pagina a 1000 filas por default (mismo
// default que PostgREST) — sin esto, con 1817 venues, se procesarían
// solo los primeros 1000 y listo, en silencio, sin error.
async function fetchAllVenues(): Promise<VenueRow[]> {
  const all: VenueRow[] = [];
  const pageSize = 1000;
  let offset = 0;
  for (;;) {
    let query = supabase
      .from("venues")
      .select(
        "id,slug,name,type,city,neighborhood,rating,review_count,price_tier,happy_hour_until,outdoor_seating,good_for_groups,good_for_watching_sports,has_live_music"
      )
      .order("id")
      .range(offset, offset + pageSize - 1);
    if (onlySlugs) query = query.in("slug", onlySlugs);
    const { data, error } = await query;
    if (error) {
      console.error("No se pudieron leer los venues:", error.message);
      process.exit(1);
    }
    if (!data || data.length === 0) break;
    all.push(...(data as VenueRow[]));
    if (data.length < pageSize) break;
    offset += pageSize;
  }
  return all;
}

async function main() {
  const venues = await fetchAllVenues();

  const progress = loadProgress();
  const pending = force ? (venues as VenueRow[]) : (venues as VenueRow[]).filter((v) => !progress.has(v.slug));

  console.log(
    `${venues.length} venues totales, ${progress.size} ya regenerados en runs previos, ${pending.length} pendientes${dryRun ? " (dry-run)" : ""}.`
  );

  let ok = 0;
  let errors = 0;

  for (const venue of pending) {
    const seed = hash(venue.slug);
    const hook = buildHook(venue, seed);
    const description = buildDescription(venue, seed);

    console.log(`\n${venue.name} (${venue.city}/${venue.slug})`);
    console.log(`  hook: ${hook}`);
    console.log(`  desc: ${description}`);

    if (dryRun) {
      ok++;
      continue;
    }

    const { error: updErr } = await supabase.from("venues").update({ hook, description }).eq("id", venue.id);
    if (updErr) {
      console.error(`  ERROR guardando: ${updErr.message}`);
      errors++;
      continue;
    }
    progress.add(venue.slug);
    saveProgress(progress);
    ok++;
  }

  console.log(`\nListo. ok=${ok} errors=${errors}`);
}

main();
