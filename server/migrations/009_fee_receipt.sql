-- Whether Stripe was asked to email the receipt for a fee that went through (the Cancellation &
-- No-Show Policy promises a receipt for every fee: docs/legal/OWNER-CHECKLIST.md §3 item 19), so
-- Izzy Clipz Business and the website's Business area can say, in plain words, when it wasn't.
-- Never the address itself: the server reads it from Stripe (the Checkout Session that saved the
-- card) when the fee goes through, sets it on the fee's PaymentIntent, and keeps no copy.
--   sent      Stripe has the receipt email, and emails the receipt (in live mode).
--   no_email  Stripe has no email for this client: no receipt was sent.
--   failed    Stripe couldn't be asked: no receipt was sent.
-- NULL: no fee charged, a fee charged before this column, or one whose receipt is being asked for.
-- Additive only: every existing row stays valid, and the code already live keeps working on it.
ALTER TABLE appointments
  ADD COLUMN no_show_fee_receipt text NULL CHECK (no_show_fee_receipt IN ('sent', 'no_email', 'failed'));
