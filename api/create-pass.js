/**
 * Vercel Serverless Function — /api/create-pass
 *
 * Recibe datos del wallet de BarPass y crea (o actualiza)
 * un pase en PassKit.com, devolviendo la URL de descarga.
 *
 * POST /api/create-pass
 * Body: { walletId, userName, balance, points, tier, email }
 *
 * Response: { url, passId }
 */

const SECRET = process.env.BP_SECRET || 'BP_S3CR3T_2024_M1AM1';

// ── QR hash (mismo algoritmo que credential.html / pos.html) ──────
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

// QR válido por 24h (para el pase estático de Apple Wallet)
function makeWalletQR(walletId) {
  const ts = Math.floor(Date.now() / 1000 / 86400) * 86400;
  const hash = simpleHash(walletId + ':' + ts + ':' + SECRET);
  return `BP:${walletId}:${ts}:${hash}`;
}

// ── Tier labels ───────────────────────────────────────────────────
const TIER_LABELS = {
  bronze:   'Bronze Member 🥉',
  silver:   'Silver Member 🥈',
  gold:     'Gold Member 🥇',
  platinum: 'Platinum Member 💎',
};

// ── Construir el payload para PassKit.com ─────────────────────────
function buildPassKitPayload(walletData) {
  const { walletId, userName, balance, points, tier } = walletData;
  return {
    // Estos field names deben coincidir con los que definas en tu
    // template de PassKit.com (Store Card)
    "barcodeMessage":  makeWalletQR(walletId),
    "barcodeAltText":  walletId,
    "headerFields": [
      { "key": "balance", "value": `$${parseFloat(balance).toFixed(2)}`, "label": "BALANCE" }
    ],
    "primaryFields": [
      { "key": "name", "value": userName, "label": "MEMBER" }
    ],
    "secondaryFields": [
      { "key": "tier",   "value": TIER_LABELS[tier] || 'Bronze Member 🥉', "label": "LEVEL" },
      { "key": "points", "value": `${Number(points).toLocaleString()} pts`, "label": "POINTS" }
    ],
    "auxiliaryFields": [
      { "key": "walletId", "value": walletId, "label": "WALLET ID" }
    ],
    "backFields": [
      {
        "key": "usage",
        "label": "¿CÓMO USAR?",
        "value": "Muestra el QR al bartender para pagar con tu BarPass Wallet. El QR se renueva diariamente por seguridad."
      },
      {
        "key": "support",
        "label": "SOPORTE",
        "value": "support@barpass.io"
      },
      {
        "key": "terms",
        "label": "TÉRMINOS",
        "value": "Saldo no reembolsable. Válido solo en venues BarPass Miami."
      }
    ]
  };
}

// ── Handler principal ─────────────────────────────────────────────
export default async function handler(req, res) {
  // CORS — permite requests desde GitHub Pages y localhost
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  // Validar que tenemos la API key configurada
  const PASSKIT_API_KEY = process.env.PASSKIT_API_KEY;
  const PASSKIT_TEMPLATE = process.env.PASSKIT_TEMPLATE_NAME || 'barpass-wallet';

  if (!PASSKIT_API_KEY) {
    return res.status(500).json({
      error: 'PASSKIT_API_KEY not configured',
      hint: 'Add it in Vercel → Settings → Environment Variables'
    });
  }

  // Parsear body
  let body;
  try {
    body = typeof req.body === 'string' ? JSON.parse(req.body) : req.body;
  } catch {
    return res.status(400).json({ error: 'Invalid JSON body' });
  }

  const { walletId, userName, balance, points, tier, email } = body;
  if (!walletId || !userName) {
    return res.status(400).json({ error: 'walletId and userName are required' });
  }

  const payload = buildPassKitPayload({ walletId, userName, balance, points, tier });

  try {
    // ── Intentar actualizar primero, crear si no existe ──────────
    let passKitResponse;
    let passData;

    // 1) Intentar GET para ver si ya existe el pass con este serial
    const checkRes = await fetch(
      `https://api.passkit.com/v1/pass/${PASSKIT_TEMPLATE}/${walletId}`,
      {
        headers: {
          'Authorization': `ApiKey ${PASSKIT_API_KEY}`,
          'Content-Type': 'application/json',
        }
      }
    );

    if (checkRes.ok) {
      // Ya existe — hacer PATCH para actualizar
      passKitResponse = await fetch(
        `https://api.passkit.com/v1/pass/${PASSKIT_TEMPLATE}/${walletId}`,
        {
          method: 'PATCH',
          headers: {
            'Authorization': `ApiKey ${PASSKIT_API_KEY}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify(payload)
        }
      );
    } else {
      // No existe — crear nuevo con el walletId como serial number
      passKitResponse = await fetch(
        `https://api.passkit.com/v1/pass/${PASSKIT_TEMPLATE}`,
        {
          method: 'POST',
          headers: {
            'Authorization': `ApiKey ${PASSKIT_API_KEY}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            ...payload,
            serialNumber: walletId,
            // email para notificaciones si PassKit lo soporta
            ...(email ? { email } : {})
          })
        }
      );
    }

    if (!passKitResponse.ok) {
      const errText = await passKitResponse.text();
      console.error('PassKit API error:', passKitResponse.status, errText);
      return res.status(502).json({
        error: 'PassKit API error',
        status: passKitResponse.status,
        details: errText
      });
    }

    passData = await passKitResponse.json();

    // PassKit devuelve la URL de descarga del .pkpass
    // El formato exacto depende de la versión de su API
    const downloadUrl =
      passData.url ||
      passData.downloadUrl ||
      passData.passUrl ||
      passData.links?.download ||
      `https://pub1.pskt.io/c/${passData.id || passData.passId}`;

    return res.status(200).json({
      ok: true,
      url: downloadUrl,
      passId: passData.id || passData.passId || walletId,
      qr: makeWalletQR(walletId)
    });

  } catch (err) {
    console.error('create-pass error:', err);
    return res.status(500).json({
      error: 'Internal server error',
      message: err.message
    });
  }
}
