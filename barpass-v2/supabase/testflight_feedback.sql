-- Feedback de TestFlight (screenshots + crashes) traído automáticamente
-- por scripts/check-testflight-feedback.ts vía la App Store Connect API.
-- external_id = el id que Apple le da a cada submission — es la clave
-- para no procesar lo mismo dos veces.

CREATE TABLE IF NOT EXISTS testflight_feedback (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  external_id text UNIQUE NOT NULL,
  kind text NOT NULL CHECK (kind IN ('screenshot', 'crash')),
  comment text,
  tester_email text,
  device_model text,
  os_version text,
  app_version text,
  submitted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS testflight_feedback_submitted_at_idx ON testflight_feedback (submitted_at DESC);
