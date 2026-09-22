/**
 * Esta prueba es lo único que hace que el arreglo dure.
 *
 * El 14 de septiembre de 2026 un barrido de 2.510 venues costó USD 655 en un
 * día porque once scripts distintos llamaban cada uno por su cuenta a Google
 * Places, cada uno con su field mask angosto, pagando el nivel de campo caro
 * una vez por script. Se migraron los once a `scripts/lib/places-client.ts`.
 *
 * Sin esta prueba, el arreglo dura hasta que alguien escriba el script número
 * doce — y va a escribirlo copiando y pegando uno de los viejos, que es
 * exactamente como llegamos acá. Así que: si aparece un request a Google
 * fuera de `scripts/lib/`, esto falla y dice qué hacer.
 *
 *   cd barpass-v2 && npx vitest run scripts/no-direct-places-calls.test.ts
 */
import { describe, expect, it } from "vitest";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { PlacesClient } from "./lib/places-client";

const SELF = fileURLToPath(import.meta.url);
const SCRIPTS_DIR = path.dirname(SELF);

/** El directorio donde SÍ se puede hablar con Google. Todo lo demás pasa por él. */
const CLIENT_DIR = path.join(SCRIPTS_DIR, "lib");

const SCANNED_EXTENSIONS = new Set([".ts", ".tsx", ".mts", ".mjs", ".js"]);

/** Sólo node_modules. Todo subdirectorio de scripts/ se revisa —
 *  `kimi-handoff/load-age-brackets.ts` también llamaba a Google por su cuenta,
 *  y una excepción por carpeta es exactamente por dónde se vuelve a escapar. */
const SKIPPED_DIRS = new Set(["node_modules"]);

/**
 * Tres señales, no una. El host solo no alcanza: alguien puede armar la URL
 * por pedazos. La clave y el header de autenticación son igual de delatores, y
 * además ninguno de los dos tiene por qué aparecer nunca más fuera del cliente.
 */
const FORBIDDEN: { pattern: string; why: string }[] = [
  {
    pattern: "https://places.googleapis.com",
    why: "arma un request a Places por su cuenta",
  },
  {
    pattern: "X-Goog-Api-Key",
    why: "manda el header de autenticación de Google por su cuenta",
  },
  {
    pattern: "GOOGLE_PLACES_API_KEY",
    why: "lee la clave facturable (la lee el cliente, no el script)",
  },
];

/**
 * Una línea de comentario no gasta plata. `backfill-field-provenance.ts`
 * menciona el host en su cabecera para explicar una decisión vieja, y varios
 * scripts nombran la variable de entorno en sus instrucciones de uso.
 *
 * LÍMITE CONOCIDO: sólo reconoce líneas que EMPIEZAN como comentario. Un
 * comentario al final de una línea de código va a dar falso positivo — el
 * mensaje de error dice cómo, y reescribir esa línea es más barato que un
 * parser de TypeScript acá adentro.
 */
function isCommentLine(line: string): boolean {
  const t = line.trim();
  return t.startsWith("//") || t.startsWith("*") || t.startsWith("/*");
}

function walk(dir: string, out: string[] = []): string[] {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name.startsWith(".")) continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (SKIPPED_DIRS.has(entry.name)) continue;
      walk(full, out);
      continue;
    }
    if (SCANNED_EXTENSIONS.has(path.extname(entry.name))) out.push(full);
  }
  return out;
}

interface Offence {
  file: string;
  line: number;
  pattern: string;
  why: string;
  text: string;
}

function findOffences(): Offence[] {
  const offences: Offence[] = [];
  for (const file of walk(SCRIPTS_DIR)) {
    // El cliente tiene permitido hablar con Google: es su trabajo. Y esta
    // prueba nombra los patrones prohibidos, así que no puede juzgarse a sí
    // misma (se compara por ruta, no por nombre, para que sobreviva un rename).
    if (file === SELF) continue;
    if (file.startsWith(CLIENT_DIR + path.sep)) continue;

    const lines = fs.readFileSync(file, "utf-8").split("\n");
    lines.forEach((text, i) => {
      if (isCommentLine(text)) return;
      for (const { pattern, why } of FORBIDDEN) {
        if (text.includes(pattern)) {
          offences.push({
            file: path.relative(SCRIPTS_DIR, file),
            line: i + 1,
            pattern,
            why,
            text: text.trim().slice(0, 100),
          });
        }
      }
    });
  }
  return offences;
}

describe("ningún script llama a Google Places por fuera del cliente", () => {
  it("no hay requests directos a Places en scripts/", () => {
    const offences = findOffences();
    const report = offences
      .map((o) => `  ${o.file}:${o.line} — ${o.why}\n      ${o.text}`)
      .join("\n");

    expect(
      offences,
      offences.length === 0
        ? ""
        : `\n${offences.length} llamada(s) directa(s) a Google Places fuera de scripts/lib/:\n${report}\n\n` +
            `Cada request paga el nivel de campo completo. Usá el cliente medido:\n` +
            `  import { placesClient, unwrap } from "./lib/places-calls";\n` +
            `  const places = placesClient("mi-script");\n` +
            `  const data = await unwrap(() => places.placeDetails(id, ["campo1","campo2"]), "qué es");\n` +
            `y pedí TODOS los campos que necesites en UNA sola llamada, no una pasada por campo.\n` +
            `Si la línea marcada es sólo un comentario al final de código, movelo a su propia línea.\n`,
    ).toEqual([]);
  });

  /**
   * Las cuatro puertas que los scripts migrados usan. Si el cliente cambia un
   * nombre, esto falla acá con un mensaje claro en vez de fallar disperso en
   * once scripts.
   */
  it("el cliente expone las cuatro puertas que usan los scripts", () => {
    for (const fn of ["placeDetails", "searchText", "searchNearby", "photo"] as const) {
      expect(typeof PlacesClient.prototype[fn], `PlacesClient debe tener ${fn}()`).toBe("function");
    }
  });

  /**
   * El dry-run del cliente es lo que hace que un error de migración salga
   * gratis. Si alguien lo invierte a "gastar por defecto", que falle acá.
   */
  it("un cliente recién construido no gasta hasta que se lo pidan", () => {
    // Se prueba el DEFAULT, así que la variable de entorno del que corre el
    // test no puede opinar. Se saca y se devuelve.
    const previous = process.env.PLACES_SPEND;
    delete process.env.PLACES_SPEND;
    try {
      expect(new PlacesClient({ label: "test", reportOnExit: false }).isDryRun).toBe(true);
    } finally {
      if (previous !== undefined) process.env.PLACES_SPEND = previous;
    }
  });
});
