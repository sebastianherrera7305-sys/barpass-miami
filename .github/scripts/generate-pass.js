/**
 * GitHub Actions script — genera un Apple Wallet pass via PassKit.com
 * y guarda el resultado en passes/{walletId}.json
 *
 * Variables de entorno requeridas (GitHub Secrets):
 *   PASSKIT_API_KEY      — tu API key de PassKit.com
 *   PASSKIT_TEMPLATE     — nombre del programa en PassKit (ej: barpass-wallet)
 *   BP_SECRET            — secreto compartido para el hash del QR
 *   WALLET_PAYLOAD       — JSON con los datos del wallet (inyectado por el workflow)
 */

import { writeFileSync, mkdirSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import fetch from 'node-fetch';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, '../../');

// ── Leer payload del wallet ───────────────────────────────────────
const raw = process.env.WALLET_PAYLOAD || '{}';
let payload;
try {
  payload = JSON.parse(raw);
} catch (e) {
  console.error('❌ WALLET_PAYLOAD inválido:', raw);
  process.exit(1);
}

const {
  walletId,
  userName   = 'BarPass Member',
  balance    = 0,
  points     = 0,
  tier       = 'bronze',
  email      = '',
} = payload;

if (!walletId) {
  console.error('❌ walletId es requerido en client_payload');
  process.exit(1);
}

console.log(`🎫 Generando pase para wallet: ${walletId} (${userName})`);

// ── QR hash (mismo algoritmo que credential.html) ─────────────────
const SECRET = process.env.BP_SECRET || 'BP_S3CR3T_2024_M1AM1';

function simpleHash(str) {
  let h1 = 0xdeadbeef, h2 = 0x41c6ce57;
  for (let i = 0; i < str.length; i++) {
    const ch = str.charCodeAt(i);
    h1 = Math.imul(h1 ^ ch, 0x9e3779b9);
    h2 = Math.imul(h2 ^ ch, 0x5c4bcfad);
  }
  h1 = Math.imul(h1 ^ (h1 >>> 16), 0x45d9f3b) ^ Math.imul(h2 ^ (h2 >>> 13), 0x45d9f3b);
  h2 = Math.imul(h2 ^ (h2 >>> 16), 0x45d9f3b) ^ Math.imul(h1 ^ (h1 >>> 13), 0x45d9f3b);
  return ((h2 >>> 0) * 0x100000000 + (h1 >>> 0))
    .toString(16).padStart(16, '0').toUpperCase().slice(0, 8);
}

// QR con TTL de 24h (para el pase estático)
function makeWalletQR(wid) {
  const ts = Math.floor(Date.now() / 1000 / 86400) * 86400;
  const hash = simpleHash(wid + ':' + ts + ':' + SECRET);
  return `BP:${wid}:${ts}:${hash}`;
}

// ── Tier labels ───────────────────────────────────────────────────
const TIER_LABELS = {
  bronze:   'Bronze Member 🥉',
  silver:   'Silver Member 🥈',
  gold:     'Gold Member 🥇',
  platinum: 'Platinum Member 💎',
};

// ── Construir payload PassKit ─────────────────────────────────────
function buildPassKitPayload() {
  return {
    serialNumber:   walletId,
    barcodeMessage: makeWalletQR(walletId),
    barcodeAltText: walletId,
    headerFields: [
      { key: 'balance', value: `$${parseFloat(balance).toFixed(2)}`, label: 'BALANCE' }
    ],
    primaryFields: [
      { key: 'name', value: userName, label: 'MEMBER' }
    ],
    secondaryFields: [
      { key: 'tier',   value: TIER_LABELS[tier] || TIER_LABELS.bronze, label: 'LEVEL' },
      { key: 'points', value: `${Number(points).toLocaleString()} pts`,  label: 'POINTS' }
    ],
    auxiliaryFields: [
      { key: 'walletId', value: walletId, label: 'WALLET ID' }
    ],
    backFields: [
      {
        key:   'usage',
        label: '¿CÓMO USAR?',
        value: 'Muestra el QR al bartender. Se renueva diariamente.'
      },
      { key: 'support', label: 'SOPORTE', value: 'support@barpass.io' }
    ],
    ...(email ? { email } : {})
  };
}

// ── Llamar a PassKit API ──────────────────────────────────────────
async function callPassKit() {
  const API_KEY  = process.env.PASSKIT_API_KEY;
  const TEMPLATE = process.env.PASSKIT_TEMPLATE || 'barpass-wallet';

  if (!API_KEY) {
    console.warn('⚠️  PASSKIT_API_KEY no configurada — guardando URL de demo');
    return {
      url:    `https://sebastianherrera7305-sys.github.io/barpass-miami/passes/demo.pkpass`,
      passId: walletId,
      demo:   true
    };
  }

  const body = buildPassKitPayload();
  console.log('📤 Payload:', JSON.stringify(body, null, 2));

  // 1) Intentar actualizar si ya existe
  const checkUrl = `https://api.passkit.com/v1/pass/${TEMPLATE}/${walletId}`;
  const checkRes = await fetch(checkUrl, {
    headers: { 'Authorization': `ApiKey ${API_KEY}` }
  });

  let res;
  if (checkRes.ok) {
    console.log('🔄 Pase existente — actualizando…');
    res = await fetch(checkUrl, {
      method:  'PATCH',
      headers: { 'Authorization': `ApiKey ${API_KEY}`, 'Content-Type': 'application/json' },
      body:    JSON.stringify(body)
    });
  } else {
    console.log('✨ Creando nuevo pase…');
    res = await fetch(`https://api.passkit.com/v1/pass/${TEMPLATE}`, {
      method:  'POST',
      headers: { 'Authorization': `ApiKey ${API_KEY}`, 'Content-Type': 'application/json' },
      body:    JSON.stringify(body)
    });
  }

  const text = await res.text();
  console.log(`📥 PassKit response (${res.status}):`, text);

  if (!res.ok) {
    throw new Error(`PassKit API ${res.status}: ${text}`);
  }

  const data = JSON.parse(text);
  const url  =
    data.url         ||
    data.downloadUrl ||
    data.passUrl     ||
    data.links?.download ||
    `https://pub1.pskt.io/c/${data.id || data.passId}`;

  return { url, passId: data.id || data.passId || walletId, demo: false };
}

// ── Main ──────────────────────────────────────────────────────────
async function main() {
  try {
    const result = await callPassKit();

    // Guardar en passes/{walletId}.json
    const passesDir = join(ROOT, 'passes');
    mkdirSync(passesDir, { recursive: true });

    const outPath = join(passesDir, `${walletId}.json`);
    const outData = {
      walletId,
      url:       result.url,
      passId:    result.passId,
      demo:      result.demo,
      generatedAt: new Date().toISOString(),
    };

    writeFileSync(outPath, JSON.stringify(outData, null, 2));
    console.log(`✅ Guardado en passes/${walletId}.json`);
    console.log(`🔗 URL del pase: ${result.url}`);

  } catch (err) {
    console.error('❌ Error:', err.message);

    // Guardar error en el JSON para que credential.html lo detecte
    const passesDir = join(ROOT, 'passes');
    mkdirSync(passesDir, { recursive: true });
    writeFileSync(
      join(passesDir, `${walletId}.json`),
      JSON.stringify({ walletId, error: err.message, generatedAt: new Date().toISOString() })
    );
    process.exit(1);
  }
}

main();
