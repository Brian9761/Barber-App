-- No-show protection: a card saved before booking (Stripe Checkout in setup
-- mode), the owner's fee settings, and on each protected appointment the fee
-- agreed at booking, the policy the client agreed to (with the late-cancellation
-- window, if it had one), and what happened when the shop charged it. The same
-- fee covers a no-show and a late cancellation (the client cancelled less than
-- the window before the start); the "no_show_fee_*" columns are for either.
-- Nothing is charged at booking. Card numbers never reach this database: only
-- the brand, last 4 digits, expiry and Stripe's ids.

-- Small shop-wide settings, one JSON value per key (e.g. 'no_show').
CREATE TABLE settings (
  key        text PRIMARY KEY CHECK (key ~ '^[a-z][a-z0-9_]*$'),
  value      jsonb NOT NULL CHECK (jsonb_typeof(value) = 'object'),
  updated_at timestamptz NOT NULL
);

-- A card a client saved for no-show protection. The app makes the card token
-- (32 random bytes, base64url, like a manage token) and keeps it in the
-- Keychain; only its SHA-256 is stored. One token, one card; one Checkout
-- Session, one card.
CREATE TABLE saved_cards (
  id                       uuid PRIMARY KEY,
  token_hash               text NOT NULL CHECK (token_hash ~ '^[0-9a-f]{64}$'),
  checkout_session_id      text NOT NULL CHECK (checkout_session_id ~ '^cs_[A-Za-z0-9_]+$'),
  stripe_customer_id       text NOT NULL CHECK (stripe_customer_id ~ '^cus_[A-Za-z0-9_]+$'),
  stripe_payment_method_id text NOT NULL CHECK (stripe_payment_method_id ~ '^pm_[A-Za-z0-9_]+$'),
  brand                    text NOT NULL CHECK (brand ~ '^[a-z0-9_]{1,40}$'),
  last4                    text NOT NULL CHECK (last4 ~ '^[0-9]{4}$'),
  exp_month                integer NOT NULL CHECK (exp_month BETWEEN 1 AND 12),
  exp_year                 integer NOT NULL CHECK (exp_year BETWEEN 2000 AND 9999),
  -- Saved with a live key (true) or a test key (false); a test card can't book once the shop is live.
  livemode                 boolean NOT NULL,
  created_at               timestamptz NOT NULL,
  CONSTRAINT saved_cards_token_hash_key UNIQUE (token_hash),
  CONSTRAINT saved_cards_checkout_session_id_key UNIQUE (checkout_session_id)
);

ALTER TABLE appointments
  -- The card on file and the terms the client agreed to when booking (all set, or none).
  ADD COLUMN saved_card_id uuid NULL REFERENCES saved_cards (id),
  ADD COLUMN card_brand text NULL CHECK (card_brand ~ '^[a-z0-9_]{1,40}$'),
  ADD COLUMN card_last4 text NULL CHECK (card_last4 ~ '^[0-9]{4}$'),
  ADD COLUMN no_show_fee_cents integer NULL CHECK (no_show_fee_cents BETWEEN 50 AND 100000),
  -- The exact policy text the client saw and agreed to, and when (the booking time).
  ADD COLUMN no_show_policy text NULL CHECK (char_length(no_show_policy) BETWEEN 1 AND 1200),
  ADD COLUMN no_show_consent_at timestamptz NULL,
  -- The late-cancellation window in the agreed policy (minutes before the start), or NULL when
  -- it had none (late cancellations were off): then cancelling in the app before the start is free.
  ADD COLUMN late_cancel_window_minutes integer NULL CHECK (late_cancel_window_minutes BETWEEN 30 AND 2880),
  -- Charging it: none → pending (asked Stripe, no final answer yet) → charged | declined | needs_action.
  ADD COLUMN no_show_fee_status text NOT NULL DEFAULT 'none'
    CHECK (no_show_fee_status IN ('none', 'pending', 'charged', 'declined', 'needs_action')),
  -- How many PaymentIntents were asked for; part of Stripe's idempotency key, so a retry after a
  -- lost answer reuses the same one and a new try (after a decline) makes a new one.
  ADD COLUMN no_show_fee_attempt integer NOT NULL DEFAULT 0 CHECK (no_show_fee_attempt >= 0),
  -- When the current attempt started: a retry looks for that attempt's PaymentIntent at Stripe
  -- from then on, since Stripe may forget an idempotency key after 24 hours.
  ADD COLUMN no_show_fee_attempt_at timestamptz NULL,
  -- What the current attempt charges for: a no-show, or a late cancellation by the client.
  ADD COLUMN no_show_fee_reason text NULL CHECK (no_show_fee_reason IN ('no_show', 'late_cancel')),
  ADD COLUMN no_show_fee_payment_intent_id text NULL CHECK (no_show_fee_payment_intent_id ~ '^pi_[A-Za-z0-9_]+$'),
  -- Why it was declined or needs the client, in plain words for the owner.
  ADD COLUMN no_show_fee_message text NULL CHECK (char_length(no_show_fee_message) <= 300),
  ADD COLUMN no_show_fee_charged_at timestamptz NULL,
  -- When the client cancelled in the app, or asked to, before the start. Set once and never
  -- cleared, not even when the shop reopens the booking: such a booking is never charged a
  -- no-show fee. Less than late_cancel_window_minutes before the start, it's a late
  -- cancellation, which can be charged the fee (only while it stays cancelled by the client).
  ADD COLUMN customer_cancelled_at timestamptz NULL,
  ADD CONSTRAINT appointments_no_show_fee_attempt_at CHECK ((no_show_fee_attempt = 0) = (no_show_fee_attempt_at IS NULL)),
  ADD CONSTRAINT appointments_no_show_fee_reason CHECK ((no_show_fee_attempt = 0) = (no_show_fee_reason IS NULL)),
  ADD CONSTRAINT appointments_no_show_terms CHECK (
    (saved_card_id IS NULL) = (card_brand IS NULL)
    AND (saved_card_id IS NULL) = (card_last4 IS NULL)
    AND (saved_card_id IS NULL) = (no_show_fee_cents IS NULL)
    AND (saved_card_id IS NULL) = (no_show_policy IS NULL)
    AND (saved_card_id IS NULL) = (no_show_consent_at IS NULL)
    AND (saved_card_id IS NOT NULL OR late_cancel_window_minutes IS NULL)
  ),
  ADD CONSTRAINT appointments_no_show_fee_needs_terms CHECK (no_show_fee_status = 'none' OR saved_card_id IS NOT NULL),
  ADD CONSTRAINT appointments_no_show_fee_charged CHECK ((no_show_fee_status = 'charged') = (no_show_fee_charged_at IS NOT NULL));

-- Card payments taken in the shop (Tap to Pay), and fees charged to a card on file: for a
-- no-show, or for a late cancellation.
ALTER TABLE payments
  ADD COLUMN kind text NOT NULL DEFAULT 'in_person' CHECK (kind IN ('in_person', 'no_show_fee', 'late_cancel_fee'));
