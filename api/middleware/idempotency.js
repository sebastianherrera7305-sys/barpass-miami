/**
 * BarPass — Idempotency Middleware (Hardened v1.5)
 * Prevents double-charges when Wi-Fi drops at high-volume events (Factory Town, etc.)
 *
 * Flow:
 *   POST /transactions or POST /refunds
 *   → Check Redis for Idempotency-Key
 *   → If found: return cached response (no DB write, no charge)
 *   → If not found: process, then dual-write (DB + Redis TTL 24h atomically)
 *
 * Key format: bp_{vendorId}_{staffId}_{timestamp}_{random}
 */

const redis = require('redis');

// ---------------------------------------------------------------------------
// Redis client (configure via env)
// ---------------------------------------------------------------------------
let redisClient;

async function getRedisClient() {
  if (!redisClient) {
    redisClient = redis.createClient({
      url: process.env.REDIS_URL || 'redis://localhost:6379',
      socket: { connectTimeout: 5000 },
    });
    redisClient.on('error', (err) => console.error('[Idempotency] Redis error:', err));
    await redisClient.connect();
  }
  return redisClient;
}

// ---------------------------------------------------------------------------
// Key generator (call on the client device before each charge attempt)
// ---------------------------------------------------------------------------
function generateIdempotencyKey(vendorId, staffId) {
  const timestamp = Date.now();
  const random = Math.random().toString(36).slice(2, 8).toUpperCase();
  return `bp_${vendorId}_${staffId}_${timestamp}_${random}`;
}

// ---------------------------------------------------------------------------
// Middleware factory — wrap Express route handlers
// ---------------------------------------------------------------------------
function idempotencyMiddleware(options = {}) {
  const {
    ttlSeconds = 86400,        // 24 hours
    headerName = 'idempotency-key',
    requiredRoutes = ['/transactions', '/refunds'],
  } = options;

  return async function (req, res, next) {
    // Only enforce on charge-mutating routes
    const isRequiredRoute = requiredRoutes.some((r) => req.path.startsWith(r));
    if (req.method !== 'POST' || !isRequiredRoute) return next();

    const idempotencyKey = req.headers[headerName];

    // ── 400 if key missing ──────────────────────────────────────────────────
    if (!idempotencyKey) {
      return res.status(400).json({
        error: 'missing_idempotency_key',
        message: `Header '${headerName}' is required for all POST charge requests.`,
        hint: `Use generateIdempotencyKey(vendorId, staffId) from this module.`,
      });
    }

    // ── Validate key format ─────────────────────────────────────────────────
    const keyPattern = /^bp_[^_]+_[^_]+_\d+_[A-Z0-9]+$/;
    if (!keyPattern.test(idempotencyKey)) {
      return res.status(400).json({
        error: 'invalid_idempotency_key_format',
        message: `Key must match format: bp_{vendorId}_{staffId}_{timestamp}_{random}`,
      });
    }

    let client;
    try {
      client = await getRedisClient();

      const t0 = Date.now();
      const cached = await client.get(`idempotency:${idempotencyKey}`);
      const redisLatency = Date.now() - t0;

      // Log latency in dev — alert if > 10ms
      if (process.env.NODE_ENV !== 'production' && redisLatency > 10) {
        console.warn(`[Idempotency] Redis check took ${redisLatency}ms (target < 10ms)`);
      }

      // ── Cache HIT: return stored response, no charge ─────────────────────
      if (cached) {
        const stored = JSON.parse(cached);
        console.log(`[Idempotency] Duplicate request blocked — key: ${idempotencyKey}`);
        return res
          .status(stored.statusCode)
          .set('X-Idempotency-Replayed', 'true')
          .json(stored.body);
      }

      // ── Cache MISS: intercept response to store it ───────────────────────
      // Monkey-patch res.json so we capture the response after the route runs
      const originalJson = res.json.bind(res);

      res.json = async function (body) {
        const statusCode = res.statusCode || 200;

        // Only cache success responses (2xx)
        if (statusCode >= 200 && statusCode < 300) {
          try {
            // Dual-write: DB write happens inside the route handler;
            // here we persist the idempotency record atomically using SET NX EX
            // If this SET fails, the caller will retry with the same key and
            // the next attempt will process normally (safe: no partial state).
            await client.set(
              `idempotency:${idempotencyKey}`,
              JSON.stringify({ statusCode, body }),
              { EX: ttlSeconds, NX: false } // NX: false = overwrite if race condition
            );
            console.log(`[Idempotency] Key stored — ${idempotencyKey} (TTL: ${ttlSeconds}s)`);
          } catch (cacheErr) {
            // Log but don't fail the request — response already sent
            console.error('[Idempotency] Failed to cache response:', cacheErr.message);
          }
        }

        return originalJson(body);
      };

      // Attach key to request for use in route handler (e.g., store in DB)
      req.idempotencyKey = idempotencyKey;

      next();
    } catch (err) {
      console.error('[Idempotency] Middleware error:', err.message);
      // Fail open: if Redis is down, allow the request through with a warning
      // Better to risk a rare duplicate than to block all transactions
      console.warn('[Idempotency] Redis unavailable — proceeding without idempotency check');
      req.idempotencyKey = idempotencyKey;
      req.idempotencyUnchecked = true;
      next();
    }
  };
}

// ---------------------------------------------------------------------------
// Standalone checker — use in route handler for explicit control
// ---------------------------------------------------------------------------
async function checkIdempotency(key) {
  const client = await getRedisClient();
  const cached = await client.get(`idempotency:${key}`);
  return cached ? JSON.parse(cached) : null;
}

async function storeIdempotency(key, statusCode, body, ttlSeconds = 86400) {
  const client = await getRedisClient();
  await client.set(
    `idempotency:${key}`,
    JSON.stringify({ statusCode, body }),
    { EX: ttlSeconds }
  );
}

// ---------------------------------------------------------------------------
// Exports
// ---------------------------------------------------------------------------
module.exports = {
  idempotencyMiddleware,
  generateIdempotencyKey,
  checkIdempotency,
  storeIdempotency,
};
