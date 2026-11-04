-- The shop's own Stripe account, connected from Settings (Stripe Connect with
-- Account Links onboarding), and signing in on a computer with a 6-digit code
-- from the Business app. Additive only: every existing row stays valid, and the
-- code already live keeps working on this schema.

-- One-time states for the addresses Stripe sends the owner back to after
-- onboarding (GET /api/stripe/connect/return and …/refresh). The state is 32
-- random bytes in base64url; only its SHA-256 is stored. It can be loaded more
-- than once until it expires, an hour after it was made.
CREATE TABLE stripe_connect_states (
  state_hash text PRIMARY KEY CHECK (state_hash ~ '^[0-9a-f]{64}$'),
  -- Where to send the owner afterwards: the Business app, or the website's Business area.
  return_to  text NOT NULL CHECK (return_to IN ('app', 'web')),
  created_at timestamptz NOT NULL,
  expires_at timestamptz NOT NULL,
  CONSTRAINT stripe_connect_states_valid_range CHECK (expires_at > created_at)
);

CREATE INDEX stripe_connect_states_expires_idx ON stripe_connect_states (expires_at);

-- Which connected Stripe account a saved card (its Customer and PaymentMethod)
-- and a payment (an in-person payment or a fee) live on. NULL: made with the
-- server's own key (STRIPE_CONNECT off), as every row before this migration.
ALTER TABLE saved_cards
  ADD COLUMN stripe_account_id text NULL CHECK (stripe_account_id ~ '^acct_[A-Za-z0-9]+$');

ALTER TABLE payments
  ADD COLUMN stripe_account_id text NULL CHECK (stripe_account_id ~ '^acct_[A-Za-z0-9]+$');

-- The 6-digit codes the Business app shows under Settings → Use on a computer.
-- Only an HMAC of the code (keyed with the owner key) is stored. A code works
-- once, for 10 minutes, and is burned after 5 wrong tries; a new code replaces
-- the ones before it.
CREATE TABLE computer_codes (
  id              uuid PRIMARY KEY,
  code_hash       text NOT NULL CHECK (code_hash ~ '^[0-9a-f]{64}$'),
  created_at      timestamptz NOT NULL,
  expires_at      timestamptz NOT NULL,
  used_at         timestamptz NULL,
  failed_attempts integer NOT NULL DEFAULT 0 CHECK (failed_attempts >= 0),
  CONSTRAINT computer_codes_valid_range CHECK (expires_at > created_at)
);

-- A computer signed in to the website's Business area. Its token (43 characters
-- of base64url: 16 random bytes and the owner key's HMAC of them, so a new owner
-- key signs every computer out) works like the owner key on most owner routes
-- until it expires (30 days) or is revoked; only the token's SHA-256 is stored.
CREATE TABLE computer_sessions (
  id           uuid PRIMARY KEY,
  token_hash   text NOT NULL CHECK (token_hash ~ '^[0-9a-f]{64}$'),
  -- What the website calls the computer, e.g. "Chrome on Mac".
  name         text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 80),
  created_at   timestamptz NOT NULL,
  last_used_at timestamptz NOT NULL,
  expires_at   timestamptz NOT NULL,
  revoked_at   timestamptz NULL,
  CONSTRAINT computer_sessions_token_hash_key UNIQUE (token_hash),
  CONSTRAINT computer_sessions_valid_range CHECK (expires_at > created_at)
);
