/**
 * BarPass API — Express entry point
 *
 * Deploy to Vercel (vercel.json routes /* → this file) or run locally:
 *   node api/server.js
 */

require('dotenv').config();

const express      = require('express');
const helmet       = require('helmet');
const cors         = require('cors');
const rateLimit    = require('express-rate-limit');
const Stripe       = require('stripe');
const admin        = require('./db/firestore'); // initialises Firebase at import time

const transactionsRouter = require('./routes/transactions');
const walletRouter       = require('./routes/wallet');
const applePayRouter     = require('./routes/apple-pay');

const app  = express();
const PORT = process.env.PORT || 3001;

// ── Security headers ──────────────────────────────────────────────────────────
app.use(helmet({
  crossOriginResourcePolicy: { policy: 'cross-origin' },
}));

// ── CORS — allow GitHub Pages origin + localhost dev ─────────────────────────
const ALLOWED_ORIGINS = [
  'https://sebastianherrera7305-sys.github.io',
  'http://localhost:3000',
  'http://localhost:5173',
];

app.use(cors({
  origin: (origin, cb) => {
    // Allow server-to-server calls (no origin header) and listed origins
    if (!origin || ALLOWED_ORIGINS.includes(origin)) return cb(null, true);
    cb(new Error(`CORS: origin ${origin} not allowed`));
  },
  methods:     ['GET', 'POST', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'Idempotency-Key'],
}));

// ── Body parsing ──────────────────────────────────────────────────────────────
// Stripe webhooks need the raw body — keep raw before json() for that route
app.use('/api/stripe/webhook', express.raw({ type: 'application/json' }));
app.use(express.json({ limit: '256kb' }));

// ── Rate limiting ─────────────────────────────────────────────────────────────
const globalLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,  // 15 minutes
  max:      200,
  standardHeaders: true,
  legacyHeaders:   false,
  message: { error: 'too_many_requests', message: 'Slow down — try again in 15 minutes.' },
});

const chargeLimiter = rateLimit({
  windowMs: 60 * 1000,  // 1 minute
  max:      10,
  keyGenerator: (req) => req.user?.uid || req.ip,
  message: { error: 'charge_rate_limit', message: 'Too many charge attempts — wait 1 minute.' },
});

app.use(globalLimiter);
app.use('/api/transactions', chargeLimiter);
app.use('/api/apple-pay',    chargeLimiter);

// ── Routes ────────────────────────────────────────────────────────────────────
app.use('/api/transactions', transactionsRouter);
app.use('/api/wallet',       walletRouter);
app.use('/api/apple-pay',    applePayRouter);

// ── Stripe Webhook ────────────────────────────────────────────────────────────
// Handles payment_intent.succeeded from Stripe Dashboard webhook
app.post('/api/stripe/webhook', async (req, res) => {
  const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);
  const sig    = req.headers['stripe-signature'];

  let event;
  try {
    event = stripe.webhooks.constructEvent(req.body, sig, process.env.STRIPE_WEBHOOK_SECRET);
  } catch (err) {
    console.error('[Webhook] Signature verification failed:', err.message);
    return res.status(400).send(`Webhook Error: ${err.message}`);
  }

  switch (event.type) {
    case 'payment_intent.succeeded': {
      const pi = event.data.object;
      // Wallet top-ups are already credited by /apple-pay/validate.
      // This is a safety net for any other payment intents.
      console.log(`[Webhook] payment_intent.succeeded: ${pi.id}`);
      break;
    }
    case 'payment_intent.payment_failed': {
      const pi = event.data.object;
      console.warn(`[Webhook] payment_intent.payment_failed: ${pi.id}`);
      break;
    }
    default:
      // Unhandled events — acknowledge receipt
  }

  return res.json({ received: true });
});

// ── Health check ──────────────────────────────────────────────────────────────
app.get('/api/health', async (req, res) => {
  try {
    // Lightweight Firestore ping
    await admin.firestore().collection('_health').doc('ping').set({
      ts: admin.firestore.FieldValue.serverTimestamp(),
    });
    return res.json({ status: 'ok', ts: new Date().toISOString() });
  } catch (err) {
    return res.status(503).json({ status: 'degraded', error: err.message });
  }
});

// ── 404 ───────────────────────────────────────────────────────────────────────
app.use((req, res) => {
  res.status(404).json({ error: 'not_found', path: req.path });
});

// ── Global error handler ──────────────────────────────────────────────────────
// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  console.error('[Server] Unhandled error:', err.message);
  res.status(500).json({ error: 'internal_error', message: 'Something went wrong.' });
});

// ── Start (skip when imported by Vercel serverless) ───────────────────────────
if (require.main === module) {
  app.listen(PORT, () => {
    console.log(`[BarPass API] Listening on port ${PORT} (${process.env.NODE_ENV || 'development'})`);
  });
}

module.exports = app;
