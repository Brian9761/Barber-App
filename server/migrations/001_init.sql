-- Izzy Clipz v4: bookings, time off, payments, products, rate limits, review cache.
-- All timestamps are timestamptz (stored in UTC). Shop-local days are worked out
-- in the app with the catalog's time zone, never with the database's.

CREATE EXTENSION IF NOT EXISTS btree_gist;

-- The team, seeded from data/catalog.json by `npm run migrate`. Bookings lock a
-- barber's row (FOR SHARE) and time off locks it (FOR UPDATE), so a booking and
-- a new block of time off for the same barber can't interleave.
CREATE TABLE barbers (
  id     text PRIMARY KEY CHECK (id ~ '^[a-z0-9-]+$'),
  name   text NOT NULL,
  sort   integer NOT NULL DEFAULT 0,
  active boolean NOT NULL DEFAULT true
);

CREATE TABLE appointments (
  id                uuid PRIMARY KEY,
  offering_id       text NOT NULL,
  service_id        text NOT NULL,
  barber_id         text NOT NULL REFERENCES barbers (id),
  -- What the client booked, as the menu showed it at the time.
  service_name      text NOT NULL,
  barber_name       text NOT NULL,
  price_label       text NOT NULL,
  price_cents       integer NOT NULL CHECK (price_cents >= 0),
  price_kind        text NOT NULL CHECK (price_kind IN ('fixed', 'startingAt', 'includedWithCut')),
  start_at          timestamptz NOT NULL,
  end_at            timestamptz NOT NULL,
  status            text NOT NULL DEFAULT 'booked'
                    CHECK (status IN ('booked', 'cancelled', 'completed', 'no_show')),
  cancelled_by      text NULL CHECK (cancelled_by IN ('customer', 'shop')),
  booked_by         text NOT NULL CHECK (booked_by IN ('customer', 'shop')),
  customer_name     text NOT NULL CHECK (char_length(customer_name) BETWEEN 1 AND 60),
  -- E.164 US number; null for walk-ins the shop adds without one.
  customer_phone    text NULL CHECK (customer_phone ~ '^\+1[2-9][0-9]{2}[2-9][0-9]{6}$'),
  customer_email    text NULL CHECK (char_length(customer_email) <= 254),
  note              text NULL CHECK (char_length(note) <= 300),
  -- SHA-256 (hex) of the client's manage token. The token itself is never stored.
  manage_token_hash text NULL CHECK (manage_token_hash ~ '^[0-9a-f]{64}$'),
  payment_status    text NOT NULL DEFAULT 'unpaid' CHECK (payment_status IN ('unpaid', 'paid')),
  paid_cents        integer NULL CHECK (paid_cents >= 0),
  paid_at           timestamptz NULL,
  payment_intent_id text NULL,
  created_at        timestamptz NOT NULL,
  updated_at        timestamptz NOT NULL,
  CONSTRAINT appointments_valid_range CHECK (end_at > start_at),
  CONSTRAINT appointments_cancelled_by CHECK ((status = 'cancelled') = (cancelled_by IS NOT NULL)),
  -- The real guard against double booking: one barber, no overlapping live appointments.
  -- '[)' ranges let back-to-back appointments touch. Cancelled and no-show rows free the time.
  CONSTRAINT appointments_no_overlap EXCLUDE USING gist (
    barber_id WITH =,
    tstzrange(start_at, end_at, '[)') WITH &&
  ) WHERE (status = 'booked' OR status = 'completed')
);

CREATE INDEX appointments_start_idx ON appointments (start_at);
CREATE INDEX appointments_upcoming_phone_idx ON appointments (customer_phone, start_at) WHERE status = 'booked';

-- Blocked time for one barber, or the whole shop when barber_id is null.
CREATE TABLE time_off (
  id         uuid PRIMARY KEY,
  barber_id  text NULL REFERENCES barbers (id),
  start_at   timestamptz NOT NULL,
  end_at     timestamptz NOT NULL,
  reason     text NULL CHECK (char_length(reason) <= 200),
  created_at timestamptz NOT NULL,
  CONSTRAINT time_off_valid_range CHECK (end_at > start_at)
);

CREATE INDEX time_off_range_idx ON time_off USING gist (tstzrange(start_at, end_at, '[)'));

-- In-person card payments (Stripe PaymentIntents created by the owner app).
CREATE TABLE payments (
  id             text PRIMARY KEY CHECK (id ~ '^pi_[A-Za-z0-9_]+$'),
  amount_cents   integer NOT NULL CHECK (amount_cents BETWEEN 50 AND 100000),
  description    text NULL CHECK (char_length(description) <= 200),
  appointment_id uuid NULL REFERENCES appointments (id) ON DELETE SET NULL,
  status         text NOT NULL,
  receipt_email  text NULL CHECK (char_length(receipt_email) <= 254),
  created_at     timestamptz NOT NULL,
  updated_at     timestamptz NOT NULL
);

CREATE INDEX payments_created_idx ON payments (created_at);
CREATE INDEX payments_appointment_idx ON payments (appointment_id) WHERE appointment_id IS NOT NULL;

-- The shop's own products, shown (not sold) in the app.
CREATE TABLE products (
  id          uuid PRIMARY KEY,
  name        text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 80),
  description text NULL CHECK (char_length(description) <= 500),
  price_cents integer NULL CHECK (price_cents BETWEEN 0 AND 1000000),
  image_url   text NULL,
  visible     boolean NOT NULL DEFAULT true,
  sort        integer NOT NULL DEFAULT 0,
  created_at  timestamptz NOT NULL,
  updated_at  timestamptz NOT NULL
);

CREATE INDEX products_sort_idx ON products (sort, created_at);

-- Fixed-window counters (10-minute buckets) for rate limits.
CREATE TABLE rate_limits (
  key          text NOT NULL,
  window_start timestamptz NOT NULL,
  count        integer NOT NULL,
  PRIMARY KEY (key, window_start)
);

-- Our own call counters, e.g. Google Places calls per shop-local day.
-- Only counts: no third-party content is ever stored here.
CREATE TABLE api_usage (
  day     date NOT NULL,
  counter text NOT NULL,
  count   integer NOT NULL,
  PRIMARY KEY (day, counter)
);

-- Yelp content, kept at most 24 hours (Yelp API terms). Google content is never stored.
CREATE TABLE yelp_cache (
  business_id text PRIMARY KEY,
  payload     jsonb NOT NULL,
  fetched_at  timestamptz NOT NULL
);
