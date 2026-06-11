/**
 * BarPass — Transactions Route
 * POST /transactions       — charge a customer order
 * POST /transactions/refunds — reverse a charge
 * POST /transactions/generate-key — generate idempotency key server-side
 */

const express = require('express');
const router  = express.Router();
const Stripe  = require('stripe');
const { idempotencyMiddleware, generateIdempotencyKey } = require('../middleware/idempotency');
const { requireAuth, requireRole } = require('../middleware/auth');
const admin   = require('../db/firestore');

const db = admin.firestore();
const TAX_RATE = 0.07; // Florida

router.use(idempotencyMiddleware());

// ── POST /transactions ────────────────────────────────────────────────────────
router.post('/', requireAuth, async (req, res) => {
  const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);

  try {
    const { vendorId, staffId, customerId, items, paymentMethod, discountCode, stripePaymentMethodId } = req.body;

    if (!vendorId || !staffId || !items?.length) {
      return res.status(422).json({
        error:   'invalid_payload',
        message: 'vendorId, staffId, and items are required.',
      });
    }

    // Validate each line item
    for (const item of items) {
      if (!item.productId || !item.name || item.qty <= 0 || item.unitPrice < 0) {
        return res.status(422).json({ error: 'invalid_item', item });
      }
    }

    const subtotal = parseFloat(items.reduce((s, i) => s + i.qty * i.unitPrice, 0).toFixed(2));
    const tax      = parseFloat((subtotal * TAX_RATE).toFixed(2));
    const total    = parseFloat((subtotal + tax).toFixed(2));

    // Resolve Stripe payment intent for card / Apple Pay methods
    let stripePaymentIntentId = null;
    if (paymentMethod === 'card' || paymentMethod === 'apple_pay') {
      if (!stripePaymentMethodId) {
        return res.status(422).json({ error: 'missing_payment_method_id' });
      }
      const intent = await stripe.paymentIntents.create({
        amount:         Math.round(total * 100),
        currency:       'usd',
        payment_method: stripePaymentMethodId,
        confirm:        true,
        return_url:     'barpass://wallet',
        metadata: {
          vendor_id:   vendorId,
          staff_id:    staffId,
          customer_id: customerId || '',
          idempotency: req.idempotencyKey || '',
        },
      });

      if (intent.status !== 'succeeded') {
        return res.status(402).json({
          error:  'payment_not_succeeded',
          status: intent.status,
        });
      }
      stripePaymentIntentId = intent.id;
    }

    // Persist to Firestore
    const txId  = `txn_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
    const txDoc = {
      id:               txId,
      idempotency_key:  req.idempotencyKey || null,
      vendor_id:        vendorId,
      staff_id:         staffId,
      customer_id:      customerId || null,
      items,
      subtotal,
      tax,
      total,
      payment_method:   paymentMethod,
      discount_code:    discountCode || null,
      stripe_pi_id:     stripePaymentIntentId,
      status:           'completed',
      created_at:       admin.firestore.FieldValue.serverTimestamp(),
    };

    await db.collection('orders').doc(txId).set(txDoc);

    // Increment vendor daily revenue counter (non-blocking)
    const today   = new Date().toISOString().slice(0, 10);
    const statRef = db.collection('vendorStats').doc(`${vendorId}_${today}`);
    db.runTransaction(async (tx) => {
      const snap = await tx.get(statRef);
      const prev = snap.exists ? snap.data() : { revenue: 0, tx_count: 0 };
      tx.set(statRef, {
        vendor_id:  vendorId,
        date:       today,
        revenue:    parseFloat((prev.revenue + total).toFixed(2)),
        tx_count:   (prev.tx_count || 0) + 1,
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    }).catch(e => console.error('[Transaction] Stats update failed:', e.message));

    return res.status(201).json({ success: true, transaction: { ...txDoc, created_at: new Date().toISOString() } });

  } catch (err) {
    if (err.type === 'StripeCardError') {
      return res.status(402).json({ error: 'card_declined', message: err.message });
    }
    console.error('[Transaction] Error:', err.message);
    return res.status(500).json({ error: 'internal_error', message: err.message });
  }
});

// ── POST /transactions/refunds ────────────────────────────────────────────────
router.post('/refunds', requireAuth, requireRole('staff', 'manager', 'admin'), async (req, res) => {
  const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);

  try {
    const { transactionId, reason, staffId } = req.body;

    if (!transactionId || !staffId) {
      return res.status(422).json({
        error:   'invalid_payload',
        message: 'transactionId and staffId are required.',
      });
    }

    // Fetch original transaction
    const originalSnap = await db.collection('orders').doc(transactionId).get();
    if (!originalSnap.exists) {
      return res.status(404).json({ error: 'transaction_not_found' });
    }

    const original = originalSnap.data();

    if (original.status === 'refunded') {
      return res.status(409).json({ error: 'already_refunded' });
    }

    // Issue Stripe refund when applicable
    let stripeRefundId = null;
    if (original.stripe_pi_id) {
      const stripeRefund = await stripe.refunds.create({
        payment_intent: original.stripe_pi_id,
        reason:         'requested_by_customer',
      });
      stripeRefundId = stripeRefund.id;
    }

    // Build refund record
    const refundId  = `ref_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
    const refundDoc = {
      id:                       refundId,
      idempotency_key:          req.idempotencyKey || null,
      original_transaction_id:  transactionId,
      vendor_id:                original.vendor_id,
      staff_id:                 staffId,
      amount:                   original.total,
      reason:                   reason || 'customer_request',
      stripe_refund_id:         stripeRefundId,
      status:                   'refunded',
      created_at:               admin.firestore.FieldValue.serverTimestamp(),
    };

    const batch = db.batch();
    batch.set(db.collection('refunds').doc(refundId), refundDoc);
    batch.update(db.collection('orders').doc(transactionId), { status: 'refunded' });
    await batch.commit();

    return res.status(201).json({ success: true, refund: { ...refundDoc, created_at: new Date().toISOString() } });

  } catch (err) {
    if (err.type === 'StripeInvalidRequestError') {
      return res.status(400).json({ error: 'stripe_error', message: err.message });
    }
    console.error('[Refund] Error:', err.message);
    return res.status(500).json({ error: 'internal_error', message: err.message });
  }
});

// ── POST /transactions/generate-key ──────────────────────────────────────────
router.post('/generate-key', (req, res) => {
  const { vendorId, staffId } = req.body;
  if (!vendorId || !staffId) {
    return res.status(400).json({ error: 'vendorId and staffId required' });
  }
  return res.json({ key: generateIdempotencyKey(vendorId, staffId) });
});

module.exports = router;
