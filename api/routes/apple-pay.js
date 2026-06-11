/**
 * POST /api/apple-pay/validate
 *
 * Receives the raw Apple Pay payment token from the iOS app,
 * charges it via Stripe, and credits the user's Firestore wallet.
 *
 * The iOS ApplePayService sends payment.token.paymentData (base64) here
 * before marking a payment as successful on-device.
 */

const express = require('express');
const router  = express.Router();
const Stripe  = require('stripe');
const { requireAuth } = require('../middleware/auth');
const admin   = require('../db/firestore');

const db = admin.firestore();

// Bonus tiers (matches client-side display in barpass-miami.html)
function bonusFor(amount) {
  if (amount >= 500) return 50;
  if (amount >= 200) return 15;
  if (amount >= 100) return 5;
  return 0;
}

// POST /api/apple-pay/validate
router.post('/validate', requireAuth, async (req, res) => {
  const { paymentToken, amount, label } = req.body;

  if (!paymentToken || typeof amount !== 'number' || amount <= 0) {
    return res.status(400).json({
      error: 'invalid_payload',
      message: 'paymentToken (string) and amount (number > 0) are required.',
    });
  }

  // Hard cap — prevents manipulation of the amount field
  if (amount > 500) {
    return res.status(400).json({ error: 'amount_too_large', message: 'Max $500 per top-up.' });
  }

  const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);

  try {
    // 1. Charge via Stripe using the Apple Pay token
    const intent = await stripe.paymentIntents.create({
      amount:   Math.round(amount * 100), // Stripe works in cents
      currency: 'usd',
      payment_method_data: {
        type: 'card',
        card: { token: paymentToken },
      },
      confirm:            true,
      return_url:         'barpass://wallet',
      description:        label || 'BarPass Wallet Top-Up',
      receipt_email:      req.user.email || undefined,
      metadata: {
        user_id: req.user.uid,
        source:  'apple_pay_ios',
        label:   label || '',
      },
    });

    if (intent.status !== 'succeeded') {
      return res.status(402).json({
        error:   'payment_not_succeeded',
        status:  intent.status,
        message: 'Payment did not complete — do not credit the wallet.',
      });
    }

    // 2. Credit wallet atomically in Firestore
    const walletRef = db.collection('wallets').doc(req.user.uid);
    const bonus     = bonusFor(amount);
    let   newBalance;

    await db.runTransaction(async (tx) => {
      const snap    = await tx.get(walletRef);
      const current = snap.exists ? (snap.data().balance || 0) : 0;
      newBalance    = parseFloat((current + amount + bonus).toFixed(2));

      tx.set(walletRef, {
        user_id:    req.user.uid,
        balance:    newBalance,
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      const txRef = walletRef.collection('transactions').doc();
      tx.set(txRef, {
        type:           'topup',
        amount,
        bonus,
        total_credited: amount + bonus,
        balance_after:  newBalance,
        stripe_pi_id:   intent.id,
        label:          label || 'BarPass Wallet Top-Up',
        created_at:     admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    return res.status(200).json({
      ok:                true,
      balance:           newBalance,
      amount_charged:    amount,
      bonus,
      stripe_pi_id:      intent.id,
    });

  } catch (err) {
    // Stripe card errors are user-facing; everything else is internal
    if (err.type === 'StripeCardError') {
      return res.status(402).json({ error: 'card_declined', message: err.message });
    }
    console.error('[ApplePay] Validation error:', err.message);
    return res.status(500).json({ error: 'internal_error', message: 'Payment processing failed.' });
  }
});

module.exports = router;
