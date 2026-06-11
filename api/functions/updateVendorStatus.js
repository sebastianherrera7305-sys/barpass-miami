/**
 * BarPass — Cloud Function: updateVendorStatus
 * Runs every 60 seconds via Cloud Scheduler.
 * Calculates active (PREPARING) orders per vendor and updates heatmap status.
 *
 * Status logic:
 *   orders PREPARING > 10  → BUSY  (red on map)
 *   orders PREPARING 1–10  → OPEN  (green on map)
 *   orders PREPARING = 0   → OPEN  (green, idle)
 *   vendor manually closed → CLOSED (grey, skipped)
 *
 * Deploy: firebase deploy --only functions:updateVendorStatus
 */

const functions = require('firebase-functions');
const admin     = require('firebase-admin');

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

const BUSY_THRESHOLD = 10;

// ── Shared core logic ─────────────────────────────────────────────────────────
async function recalcVendorStatuses() {
  const vendorsSnap = await db
    .collection('vendors')
    .where('status', '!=', 'CLOSED')
    .get();

  if (vendorsSnap.empty) return { updated: 0, counts: [] };

  const counts = await Promise.all(
    vendorsSnap.docs.map(async (doc) => {
      const snap = await db
        .collection('orders')
        .where('vendor_id', '==', doc.id)
        .where('status', '==', 'PREPARING')
        .get();
      return { vendorId: doc.id, count: snap.size };
    })
  );

  const batch = db.batch();
  const now   = admin.firestore.FieldValue.serverTimestamp();

  counts.forEach(({ vendorId, count }) => {
    batch.update(db.collection('vendors').doc(vendorId), {
      status:               count > BUSY_THRESHOLD ? 'BUSY' : 'OPEN',
      active_orders_count:  count,
      current_wait_time:    Math.ceil(count * 2), // ~2 min per queued order
      updated_at:           now,
    });
  });

  await batch.commit();
  return { updated: counts.length, counts };
}

// ── Scheduled trigger (every 1 minute) ───────────────────────────────────────
exports.updateVendorStatus = functions
  .runWith({ timeoutSeconds: 30, memory: '256MB' })
  .pubsub.schedule('every 1 minutes')
  .onRun(async () => {
    const start = Date.now();
    try {
      const { updated } = await recalcVendorStatuses();
      console.log(`[updateVendorStatus] Done — ${updated} vendors in ${Date.now() - start}ms`);
    } catch (err) {
      console.error('[updateVendorStatus] Error:', err);
      throw err; // let Cloud Functions retry
    }
    return null;
  });

// ── HTTP trigger — manual test / ops tool ────────────────────────────────────
exports.updateVendorStatusHTTP = functions.https.onRequest(async (req, res) => {
  if (req.headers['x-barpass-secret'] !== process.env.INTERNAL_SECRET) {
    return res.status(403).json({ error: 'unauthorized' });
  }
  try {
    const result = await recalcVendorStatuses();
    return res.json(result);
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});
