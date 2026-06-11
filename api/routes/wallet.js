/**
 * Wallet endpoints — server-authoritative balance.
 *
 * GET  /api/wallet          — current balance + tier
 * GET  /api/wallet/history  — paginated transaction history
 * POST /api/wallet/spend    — deduct (venue charge, idempotent)
 */

const express = require('express');
const router  = express.Router();
const { requireAuth } = require('../middleware/auth');
const { idempotencyMiddleware } = require('../middleware/idempotency');
const admin   = require('../db/firestore');

const db = admin.firestore();

// Tier thresholds (total spend in dollars)
function tierFor(totalSpent) {
  if (totalSpent >= 2000) return 'platinum';
  if (totalSpent >= 500)  return 'gold';
  if (totalSpent >= 100)  return 'silver';
  return 'bronze';
}

// ── GET /api/wallet ───────────────────────────────────────────────────────────
router.get('/', requireAuth, async (req, res) => {
  try {
    const snap = await db.collection('wallets').doc(req.user.uid).get();

    if (!snap.exists) {
      return res.json({ balance: 0, total_spent: 0, tier: 'bronze', transactions: [] });
    }

    const data = snap.data();
    return res.json({
      balance:     data.balance     || 0,
      total_spent: data.total_spent || 0,
      tier:        tierFor(data.total_spent || 0),
      updated_at:  data.updated_at?.toDate?.() || null,
    });
  } catch (err) {
    console.error('[Wallet] GET error:', err.message);
    return res.status(500).json({ error: 'internal_error' });
  }
});

// ── GET /api/wallet/history ───────────────────────────────────────────────────
router.get('/history', requireAuth, async (req, res) => {
  try {
    const limit = Math.min(parseInt(req.query.limit) || 20, 50);

    const snap = await db
      .collection('wallets').doc(req.user.uid)
      .collection('transactions')
      .orderBy('created_at', 'desc')
      .limit(limit)
      .get();

    const txs = snap.docs.map(d => {
      const data = d.data();
      return { id: d.id, ...data, created_at: data.created_at?.toDate?.() || null };
    });

    return res.json({ transactions: txs });
  } catch (err) {
    console.error('[Wallet] History error:', err.message);
    return res.status(500).json({ error: 'internal_error' });
  }
});

// ── POST /api/wallet/spend ────────────────────────────────────────────────────
// Idempotency enforced — POS device retries on bad Wi-Fi at events
router.use('/spend', idempotencyMiddleware({ requiredRoutes: ['/spend'] }));

router.post('/spend', requireAuth, async (req, res) => {
  const { amount, venueId, description } = req.body;

  if (typeof amount !== 'number' || amount <= 0) {
    return res.status(400).json({ error: 'invalid_amount' });
  }

  const walletRef = db.collection('wallets').doc(req.user.uid);
  let newBalance, newTotalSpent;

  try {
    await db.runTransaction(async (tx) => {
      const snap    = await tx.get(walletRef);
      const current = snap.exists ? (snap.data().balance || 0) : 0;
      const spent   = snap.exists ? (snap.data().total_spent || 0) : 0;

      if (current < amount) {
        const err = new Error('insufficient_balance');
        err.statusCode = 402;
        throw err;
      }

      newBalance    = parseFloat((current - amount).toFixed(2));
      newTotalSpent = parseFloat((spent + amount).toFixed(2));

      tx.set(walletRef, {
        balance:     newBalance,
        total_spent: newTotalSpent,
        updated_at:  admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      const txRef = walletRef.collection('transactions').doc();
      tx.set(txRef, {
        type:             'spend',
        amount:           -amount,
        balance_after:    newBalance,
        idempotency_key:  req.idempotencyKey || null,
        venue_id:         venueId    || null,
        description:      description || 'Venue charge',
        created_at:       admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    return res.status(200).json({
      ok:          true,
      balance:     newBalance,
      total_spent: newTotalSpent,
      tier:        tierFor(newTotalSpent),
    });

  } catch (err) {
    if (err.message === 'insufficient_balance') {
      return res.status(402).json({ error: 'insufficient_balance', message: 'Not enough BarPass credit.' });
    }
    console.error('[Wallet] Spend error:', err.message);
    return res.status(500).json({ error: 'internal_error' });
  }
});

module.exports = router;
