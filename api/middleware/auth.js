const admin = require('../db/firestore');

/**
 * Verifies the Firebase ID token sent in the Authorization header.
 * Attaches req.user = decoded token claims (uid, email, role, etc.)
 */
async function requireAuth(req, res, next) {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) {
    return res.status(401).json({
      error: 'unauthorized',
      message: "Authorization: Bearer <firebase-id-token> header is required.",
    });
  }
  try {
    req.user = await admin.auth().verifyIdToken(header.slice(7));
    next();
  } catch (err) {
    return res.status(401).json({ error: 'invalid_token', message: err.message });
  }
}

/**
 * Role gate — call after requireAuth.
 * Custom claims set via admin.auth().setCustomUserClaims(uid, { role: 'staff' })
 */
function requireRole(...roles) {
  return (req, res, next) => {
    const role = req.user?.role || 'user';
    if (!roles.includes(role)) {
      return res.status(403).json({
        error: 'forbidden',
        message: `One of these roles required: ${roles.join(', ')}`,
      });
    }
    next();
  };
}

module.exports = { requireAuth, requireRole };
