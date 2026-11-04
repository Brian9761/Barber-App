-- Sales: what the shop sells at checkout (services, products and custom items such
-- as a gift card), paid in cash, by card with Tap to Pay, or another way (Zelle,
-- Cash App…, recorded only), and what the analytics are built from. A sale is
-- never edited or deleted: a mistake is voided, and a voided sale stops counting.
-- Names and prices are copied onto each item when it's sold, so renaming or
-- repricing a product later never changes past sales.

CREATE TABLE sales (
  id                   uuid PRIMARY KEY,
  -- The barber who gets credit for the sale.
  barber_id            text NOT NULL REFERENCES barbers (id),
  -- The appointment it checked out, if any.
  appointment_id       uuid NULL REFERENCES appointments (id) ON DELETE SET NULL,
  customer_name        text NULL CHECK (char_length(customer_name) BETWEEN 1 AND 60),
  method               text NOT NULL CHECK (method IN ('card', 'cash', 'other')),
  -- A card sale's in-person payment (Tap to Pay); one sale per payment.
  payment_intent_id    text NULL UNIQUE REFERENCES payments (id),
  total_cents          integer NOT NULL CHECK (total_cents BETWEEN 0 AND 1000000),
  sold_at              timestamptz NOT NULL,
  voided_at            timestamptz NULL,
  void_reason          text NULL CHECK (char_length(void_reason) <= 200),
  -- SHA-256 (hex) of the owner app's Idempotency-Key, like shop bookings (003).
  idempotency_key_hash text NULL CHECK (idempotency_key_hash ~ '^[0-9a-f]{64}$'),
  created_at           timestamptz NOT NULL,
  updated_at           timestamptz NOT NULL,
  CONSTRAINT sales_card_payment CHECK ((method = 'card') = (payment_intent_id IS NOT NULL)),
  CONSTRAINT sales_void_reason CHECK (voided_at IS NOT NULL OR void_reason IS NULL)
);

-- One live sale per appointment; voiding it frees the appointment for another checkout.
CREATE UNIQUE INDEX sales_live_appointment_key ON sales (appointment_id) WHERE appointment_id IS NOT NULL AND voided_at IS NULL;
-- One sale per Idempotency-Key.
CREATE UNIQUE INDEX sales_idempotency_key_hash_key ON sales (idempotency_key_hash) WHERE idempotency_key_hash IS NOT NULL;
-- The day's sales and the analytics read sales by time.
CREATE INDEX sales_sold_at_idx ON sales (sold_at);

-- What a sale sold, in the order it was rung up. (The unique (sale_id, position)
-- index also serves every lookup by sale.)
CREATE TABLE sale_items (
  id          uuid PRIMARY KEY,
  sale_id     uuid NOT NULL REFERENCES sales (id) ON DELETE CASCADE,
  position    integer NOT NULL CHECK (position >= 0),
  kind        text NOT NULL CHECK (kind IN ('service', 'product', 'custom')),
  -- The catalog's service id (services only).
  service_id  text NULL,
  -- NULL once the product is deleted; its name stays on the item.
  product_id  uuid NULL REFERENCES products (id) ON DELETE SET NULL,
  name        text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 80),
  quantity    integer NOT NULL CHECK (quantity BETWEEN 1 AND 99),
  unit_cents  integer NOT NULL CHECK (unit_cents BETWEEN 0 AND 1000000),
  total_cents integer NOT NULL,
  CONSTRAINT sale_items_total CHECK (total_cents = quantity * unit_cents),
  CONSTRAINT sale_items_service CHECK ((kind = 'service') = (service_id IS NOT NULL)),
  CONSTRAINT sale_items_product CHECK (kind = 'product' OR product_id IS NULL),
  CONSTRAINT sale_items_sale_id_position_key UNIQUE (sale_id, position)
);

-- A card checkout's ticket, kept with its payment until the payment succeeds; it's
-- then recorded as the sale, once, in the same transaction.
ALTER TABLE payments ADD COLUMN sale_draft jsonb NULL CHECK (jsonb_typeof(sale_draft) = 'object');

-- The appointment's live sale, copied here in the same transaction that records or
-- voids it (a sale never changes otherwise), so every owner view of the
-- appointment shows it. A checked-out appointment stays completed until its sale
-- is voided.
ALTER TABLE appointments
  ADD COLUMN sale_id uuid NULL REFERENCES sales (id),
  ADD COLUMN sale_total_cents integer NULL CHECK (sale_total_cents BETWEEN 0 AND 1000000),
  ADD COLUMN sale_method text NULL CHECK (sale_method IN ('card', 'cash', 'other')),
  ADD CONSTRAINT appointments_sale CHECK ((sale_id IS NULL) = (sale_total_cents IS NULL) AND (sale_id IS NULL) = (sale_method IS NULL)),
  ADD CONSTRAINT appointments_sale_completed CHECK (sale_id IS NULL OR status = 'completed');
