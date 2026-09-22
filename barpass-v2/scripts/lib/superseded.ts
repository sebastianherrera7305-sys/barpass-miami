/**
 * Aviso para los scripts que quedaron reemplazados por la pasada única
 * (`refresh-venue-from-google.ts`).
 *
 * POR QUÉ NO ALCANZA UN COMENTARIO ARRIBA DEL ARCHIVO
 * El que va a gastar la plata no está leyendo el archivo: está tipeando
 * `npm run backfill:hours` porque lo corrió el mes pasado. El comentario es
 * para el que edita; esto es para el que ejecuta.
 *
 * No bloquea ni pregunta nada — el script sigue funcionando exactamente igual.
 * Sólo imprime, antes de la primera llamada a Google, qué lo reemplaza y por
 * qué. Bloquear sería cambiarle la lógica a un script que a veces todavía hace
 * falta correr.
 */
export function warnSuperseded(options: {
  /** Este script. */
  script: string;
  /** El que lo reemplaza. */
  replacement: string;
  /** Qué se paga de más al correr éste en vez del otro. */
  why: string;
}): void {
  console.warn(
    `\n⚠  ${options.script} quedó reemplazado por ${options.replacement}.\n` +
      `   ${options.why}\n` +
      `   Places API (New) cobra CADA REQUEST una vez, al nivel más caro que\n` +
      `   toque su field mask (doc: "billed at the highest SKU applicable to\n` +
      `   your request"). Por eso pedir MÁS campos en una sola llamada no\n` +
      `   cuesta más — lo caro es la segunda pasada sobre el mismo venue.\n`,
  );
}
