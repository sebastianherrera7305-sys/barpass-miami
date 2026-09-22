/**
 * La capa fina entre los scripts de barrido y el medidor (`places-client.ts`).
 *
 * POR QUÉ EXISTE
 * `PlacesClient` devuelve un `PlacesResult<T>` de cuatro estados (ok / dryRun /
 * capped / failed) porque el medidor necesita distinguirlos para el informe de
 * costo. Los once scripts que se migraron acá ya tenían todos la misma forma
 * desde antes: "si Google no me dio algo utilizable, no escribo nada y sigo".
 * Traducir los cuatro estados a `T | null` en cada uno de los once habría sido
 * once oportunidades de equivocarse; acá se hace una vez.
 *
 * Y una cosa que el medidor no hace y los scripts sí necesitaban: reintentar.
 * `add-venues.ts` y `fix-venue-types.ts` llevaban comentarios explicando cómo
 * un solo `UND_ERR_BODY_TIMEOUT` mató un barrido de miles a mitad de camino.
 * Esa protección se conserva acá en vez de perderse en la migración: se
 * reintenta la red y 429/5xx, nunca un 4xx real — un 404 quiere decir que el
 * lugar ya no existe y reintentarlo es quemar plata.
 */
import { PlacesClient, type PlacesClientOptions, type PlacesResult } from "./places-client";

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/**
 * Un cliente por script. El medidor cachea por place_id dentro del run y su
 * informe de salida resume TODO lo que gastó ese proceso, así que dos clientes
 * en el mismo script partirían la cuenta en dos y perderían el cacheo.
 */
export function placesClient(label: string, opts: PlacesClientOptions = {}): PlacesClient {
  return new PlacesClient({ label, ...opts });
}

let dryRunNoticeShown = false;

/**
 * Corre una llamada del cliente y devuelve el objeto o null.
 *
 * null significa siempre lo mismo para el que llama: "no hay dato utilizable,
 * no escribas nada". Nunca significa "Google dijo que está vacío" — ningún
 * script debe escribir un valor vacío a partir de un null de acá.
 */
export async function unwrap<T>(
  run: () => Promise<PlacesResult<T>>,
  what: string,
  retries = 3,
): Promise<T | null> {
  for (let attempt = 0; ; attempt++) {
    let result: PlacesResult<T>;
    try {
      result = await run();
    } catch (err) {
      // Excepción de red (timeout de cuerpo, socket cortado). El medidor ya
      // contó el request: se cuentan los ENVIADOS, que es la cota correcta.
      if (attempt >= retries) {
        console.warn(`  [places] ${what}: la red falló — ${(err as Error).message}`);
        return null;
      }
      await sleep(500 * 2 ** attempt);
      continue;
    }

    switch (result.status) {
      case "ok":
        return result.data;

      case "dryRun":
        // No es que Google no tenga el dato: es que no se gastó. Se avisa una
        // vez y no por venue, para que el aviso se lea en vez de perderse
        // entre cuatro mil líneas.
        if (!dryRunNoticeShown) {
          dryRunNoticeShown = true;
          console.warn(
            "\n[places] DRY RUN: no se llamó a Google, así que no hay datos para escribir.\n" +
              "         El informe del final dice cuánto costaría. Para gastar de verdad: PLACES_SPEND=1\n",
          );
        }
        return null;

      case "capped":
        // El cliente ya explica el tope en su informe final. Acá sólo se deja
        // el venue intacto, que es lo correcto: media pasada no se inventa.
        return null;

      case "failed":
        if (result.httpStatus === 429 || result.httpStatus >= 500) {
          if (attempt >= retries) {
            console.warn(`  [places] ${what}: ${result.httpStatus} tras ${retries} reintentos`);
            return null;
          }
          await sleep(1000 * 2 ** attempt);
          continue;
        }
        console.warn(`  [places] ${what}: ${result.httpStatus} ${result.body.slice(0, 140)}`);
        return null;
    }
  }
}

/**
 * El URL canónico de Place Details para un place_id. NO hace ninguna llamada:
 * existe sólo para que los scripts puedan dejar constancia de la fuente en
 * `field_sources` sin tener que escribir el host de Google por su cuenta —
 * que es justo lo que la prueba de `no-direct-places-calls` prohíbe.
 */
export function placeDetailsUrl(placeId: string): string {
  return `https://places.googleapis.com/v1/places/${placeId}`;
}

/**
 * Resuelve un photo name al URL de CDN definitivo: dimensionado y SIN clave.
 *
 * Estaba copiado en cinco scripts con cinco variantes. Es la única forma
 * aceptable de guardar una foto de Places: las otras dos o ignoran el tamaño
 * (1,3 MB por tarjeta) o meten la clave facturable dentro de `venues.image_url`,
 * que es legible con la anon key. Si aun así vuelve algo con la clave adentro,
 * se descarta: un hueco es mejor que una clave publicada.
 */
export async function photoUri(
  client: PlacesClient,
  photoName: string,
  maxWidthPx = 1200,
): Promise<string | null> {
  const data = await unwrap<{ photoUri?: string }>(
    () => client.photo(photoName, `maxWidthPx=${maxWidthPx}&skipHttpRedirect=true`),
    `photo ${photoName.slice(0, 24)}`,
  );
  const uri = data?.photoUri ?? null;
  if (!uri) return null;
  if (uri.includes("key=") || uri.includes("AIza")) {
    console.warn("   se descarta un photoUri que todavía trae la API key");
    return null;
  }
  return uri;
}
