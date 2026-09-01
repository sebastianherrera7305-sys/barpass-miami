/**
 * Corrects venue neighborhoods from verified addresses.
 *
 * `neighborhood` turned out to be the single most-wrong column in the
 * catalogue — wrong more often than the fabricated genres were. The manual
 * genre research kept surfacing it as a side effect: Ann Arbor had four
 * venues on the Ashley/Liberty core labelled "Old West Side", Miami had eight
 * venues in "Coconut Grove" that are not in it, and one Boulder row is not
 * even in Boulder.
 *
 * IMPORTANT: geometry can DETECT these but cannot CORRECT them. The catalogue
 * has no neighborhood boundaries to test a point against, so the only source
 * of a right answer is a human reading the address. That is why these come in
 * as a file rather than as a computed fix.
 *
 * Updates by id (see apply-curated-genres.mjs for why never by name), and
 * records provenance so a later automated pass does not undo the correction.
 *
 * Usage:
 *   node scripts/fix-venue-neighborhoods.mjs <fixes.json> --dry-run
 *   node scripts/fix-venue-neighborhoods.mjs <fixes.json>
 */
import fs from 'node:fs';
const URL = process.env.NEXT_PUBLIC_SUPABASE_URL, KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!URL || !KEY) throw new Error('faltan env vars de Supabase');
const H = { apikey: KEY, Authorization: `Bearer ${KEY}`, 'Content-Type': 'application/json' };
const DRY = process.argv.includes('--dry-run');
const AT = '2026-09-01';

const rows = [];
for (let off = 0; ; off += 1000) {
  const r = await fetch(`${URL}/rest/v1/venues?select=id,name,city,neighborhood,address,field_sources&order=name`,
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
  byKey.set(k, byKey.has(k) ? null : v);
}

let fixed = 0, already = 0, missing = 0;
for (const f of JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))) {
  const hit = byKey.get(`${norm(f.name)}|${norm(f.city)}`);
  if (!hit) { console.log(`  ? ausente o ambiguo: ${f.name} (${f.city})`); missing++; continue; }
  if (hit.neighborhood === f.neighborhood) { already++; continue; }

  console.log(`  ${f.city.padEnd(14)} ${f.name.slice(0, 34).padEnd(36)} ${String(hit.neighborhood).padEnd(22)} -> ${f.neighborhood}`);
  if (DRY) continue;
  const body = {
    neighborhood: f.neighborhood,
    field_sources: { ...(hit.field_sources ?? {}),
      neighborhood: { source: 'manual_research', at: AT, confidence: 'high' } },
  };
  const up = await fetch(`${URL}/rest/v1/venues?id=eq.${hit.id}`,
    { method: 'PATCH', headers: { ...H, Prefer: 'return=minimal' }, body: JSON.stringify(body) });
  if (!up.ok) console.warn(`     FALLO ${up.status} ${(await up.text()).slice(0, 100)}`);
  else fixed++;
}
console.log(`\ncorregidos ${fixed}, ya correctos ${already}, no encontrados ${missing}${DRY ? ' (dry run)' : ''}`);
