import fs from 'node:fs';
const URL = process.env.NEXT_PUBLIC_SUPABASE_URL, KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!URL || !KEY) throw new Error('faltan env vars de Supabase');
const H = { apikey: KEY, Authorization: `Bearer ${KEY}`, 'Content-Type': 'application/json' };
const DRY = process.argv.includes('--dry-run');
const WAVE = process.argv[2];
const FORCE = process.argv.includes('--force');
const AT = '2026-09-01';

const rows = [];
for (let off = 0; ; off += 1000) {
  const r = await fetch(`${URL}/rest/v1/venues?select=id,name,city,type,music_genres,field_sources&order=name`,
    { headers: { ...H, 'Range-Unit': 'items', Range: `${off}-${off + 999}` } });
  if (!r.ok) throw new Error(`select ${r.status}: ${await r.text()}`);
  const page = await r.json();
  rows.push(...page);
  if (page.length < 1000) break;
}
const norm = s => s.toLowerCase().replace(/[^a-z0-9]/g, '');
const byKey = new Map();
for (const v of rows) {
  const k = `${norm(v.name)}|${norm(v.city ?? '')}`;
  byKey.set(k, byKey.has(k) ? null : v); // null = ambiguo
}

const wave = JSON.parse(fs.readFileSync(WAVE, 'utf8'));
let genres = 0, retyped = 0, empty = 0, missing = 0, ambiguous = 0;

for (const w of wave) {
  const hit = byKey.get(`${norm(w.name)}|${norm(w.city)}`);
  if (hit === undefined) { console.log(`  ? no existe: ${w.name} (${w.city})`); missing++; continue; }
  if (hit === null) { console.log(`  ! nombre ambiguo, saltado: ${w.name} (${w.city})`); ambiguous++; continue; }

  const update = {};
  if (!w.is_nightlife) {
    if (hit.type !== 'restaurant') { update.type = 'restaurant'; retyped++; }
  }
  if (w.exclude) update.excluded_reason = w.exclude;

  // No pisar una investigación previa con una distinta. Re-aplicar los
  // archivos viejos de wave3/other_cities sobre la base ya actualizada le
  // quitó `country` a ocho honky-tonks de Nashville: el DB iba adelante de los
  // archivos porque esa mejora se hizo directo en la base y nunca se escribió
  // de vuelta. Un archivo viejo no es una fuente más nueva.
  const prior = hit.field_sources?.music_genres;
  if (prior?.source === 'manual_research' && !FORCE) {
    const before = JSON.stringify(hit.music_genres ?? []);
    const after = JSON.stringify(w.genres);
    if (before !== after) {
      console.log(`  = ya investigado, conservo lo que hay: ${w.name} ${before} (el archivo dice ${after})`);
      continue;
    }
  }

  // La procedencia se graba SIEMPRE que un humano investigó el venue, tenga
  // géneros o no. Al principio solo la grababa cuando encontraba algo, y eso
  // devolvía a la cola cada venue investigado-sin-música: Bar Kaiju salió dos
  // veces. "No publica programación musical" es un resultado de investigación,
  // no una ausencia de investigación — y `result` distingue los dos casos sin
  // afirmar un valor que nadie dijo.
  update.field_sources = { ...(hit.field_sources ?? {}),
    music_genres: w.genres.length
      ? { source: 'manual_research', at: AT, confidence: 'high' }
      : { source: 'manual_research', at: AT, result: 'none_published' } };

  if (w.genres.length) {
    update.music_genres = w.genres;
    genres++;
  } else {
    if (hit.music_genres?.length) update.music_genres = null;
    empty++;
  }
  if (!Object.keys(update).length) continue;
  if (DRY) { console.log(`  ${w.name}: ${JSON.stringify(update.music_genres ?? update.type)}`); continue; }
  const up = await fetch(`${URL}/rest/v1/venues?id=eq.${hit.id}`,
    { method: 'PATCH', headers: { ...H, Prefer: 'return=minimal' }, body: JSON.stringify(update) });
  if (!up.ok) console.warn(`  FALLO ${w.name}: ${up.status} ${(await up.text()).slice(0, 120)}`);
}
console.log(`\n${wave.length} curados${DRY ? ' (dry run)' : ''} — generos ${genres}, sin musica ${empty}, retipados ${retyped}, no encontrados ${missing}, ambiguos ${ambiguous}`);
