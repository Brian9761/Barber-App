-- What the shop's legal documents promise (docs/legal/research.md §17 and §18,
-- docs/legal/data-inventory.md G1, G2 and G14), kept by the database. Additive
-- only: every existing row stays valid, and the code already live keeps working
-- on this schema while the new code deploys.

-- A booking with a card on file that the shop marked completed (or checked out) can't
-- become a no-show, even after it's reopened: the client came. Set the first time it's
-- completed and never cleared. Bookings completed before this migration count from
-- their last change.
ALTER TABLE appointments ADD COLUMN completed_at timestamptz NULL;
UPDATE appointments SET completed_at = updated_at WHERE status = 'completed';

-- 12 months after an appointment, the daily job removes the client's name, number, email
-- and note from it (not while a fee for it is still pending), and 12 months after a sale or
-- a card payment, the client's name and the card payment's description. The rows stay,
-- without them, so the analytics don't change. anonymized_at is when that happened.
ALTER TABLE appointments ADD COLUMN anonymized_at timestamptz NULL;
CREATE INDEX appointments_to_anonymize_idx ON appointments (end_at) WHERE anonymized_at IS NULL;
ALTER TABLE sales ADD COLUMN anonymized_at timestamptz NULL;
CREATE INDEX sales_to_anonymize_idx ON sales (sold_at) WHERE anonymized_at IS NULL;
ALTER TABLE payments ADD COLUMN anonymized_at timestamptz NULL;
CREATE INDEX payments_to_anonymize_idx ON payments (created_at) WHERE anonymized_at IS NULL;

-- Receipt emails aren't kept any more: the shop offers the receipt after the card payment,
-- and the address goes to Stripe only (Civil Code §1747.08). None stays from before.
UPDATE payments SET receipt_email = NULL WHERE receipt_email IS NOT NULL;

-- Saved cards are deleted at Stripe (the card detached, its Customer deleted) when they
-- expire, go 12 months without being used for a booking, or the client removes them (or
-- saved them without "Remember me"), as soon as no booking still needs them. The row stays,
-- because old appointments name its brand and last 4 (appointments_no_show_terms), but
-- without Stripe's ids. delete_requested_at: the client asked, and a booking still needed it.
ALTER TABLE saved_cards
  ADD COLUMN removed_at timestamptz NULL,
  ADD COLUMN delete_requested_at timestamptz NULL,
  ALTER COLUMN checkout_session_id DROP NOT NULL,
  ALTER COLUMN stripe_customer_id DROP NOT NULL,
  ALTER COLUMN stripe_payment_method_id DROP NOT NULL,
  ADD CONSTRAINT saved_cards_stripe_ids CHECK (
    removed_at IS NOT NULL
    OR (checkout_session_id IS NOT NULL AND stripe_customer_id IS NOT NULL AND stripe_payment_method_id IS NOT NULL)
  );
CREATE INDEX saved_cards_kept_idx ON saved_cards (created_at) WHERE removed_at IS NULL;
-- Which bookings still need a card, and when it was last used for one.
CREATE INDEX appointments_saved_card_idx ON appointments (saved_card_id, created_at) WHERE saved_card_id IS NOT NULL;
