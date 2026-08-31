/// Stripe publishable key configuration.
///
/// IMPORTANT: This is the *publishable* key (pk_live_… / pk_test_…), safe to ship in the
/// app binary — it is NOT the same as STRIPE_SECRET_KEY used server-side in api/.env.
/// Get it from the Stripe Dashboard → Developers → API keys, then replace the value below.
/// ⚠️  REMINDER: Replace `pk_test_` with `pk_live_` before App Store submission.
enum StripeConfig {
    static let publishableKey = "pk_test_51TmM3pHzVF9FsUCtF5sIHDMlOpgAXmrZ4oYBE6LKSyw9Pbcmkm51CTRp8z3nr899EWZe8aL10JdnFKIc9hwwOBz4003pAmZPRD"
}
