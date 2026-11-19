-- What the Privacy Policy promises about saved cards ("Saved cards"), kept by the database.
-- Additive only: every existing row stays valid, and the code already live keeps working on
-- this schema while the new code deploys.

-- Every "Add card" makes a Stripe Customer and a card page (a Checkout Session in setup mode)
-- before Stripe's page opens, and the card is only recorded in saved_cards when the app or the
-- website saves it afterwards (POST /api/cards). A card page that never gets that far (the page,
-- the tab or the app closed right after Stripe saved the card, say) is kept here, so the daily
-- job can ask Stripe to delete its card (if one was added) and its Customer. Stripe's ids only:
-- nothing about the client.
--   closed_at              its card was saved (saved_cards has it from then on, and deletes it from there)
--   abandoned_at           the daily job took it up because its card was never saved in time: from
--                          then on its card can't be saved any more
--   deleted_at             Stripe deleted its card and Customer (or had neither any more), or the
--                          shop deleted them in its Stripe Dashboard: nothing more to do
--   stripe_unreachable_at  it's on a Stripe account this server can't use any more: waiting for
--                          the shop to delete it in that account (Izzy Clipz Business and the
--                          website's Business settings list it)
-- The Customer's id goes once nothing more can be done with it.
CREATE TABLE card_checkouts (
  checkout_session_id   text PRIMARY KEY CHECK (checkout_session_id ~ '^cs_[A-Za-z0-9_]+$'),
  stripe_customer_id    text NULL CHECK (stripe_customer_id ~ '^cus_[A-Za-z0-9_]+$'),
  -- The connected account it's on (Stripe Connect); null when made with the shop's own key.
  stripe_account_id     text NULL CHECK (stripe_account_id ~ '^acct_[A-Za-z0-9]+$'),
  livemode              boolean NOT NULL,
  created_at            timestamptz NOT NULL,
  closed_at             timestamptz NULL,
  abandoned_at          timestamptz NULL,
  deleted_at            timestamptz NULL,
  stripe_unreachable_at timestamptz NULL,
  CONSTRAINT card_checkouts_closed_or_abandoned CHECK (closed_at IS NULL OR abandoned_at IS NULL),
  CONSTRAINT card_checkouts_cleanup CHECK ((deleted_at IS NULL AND stripe_unreachable_at IS NULL) OR abandoned_at IS NOT NULL),
  CONSTRAINT card_checkouts_customer CHECK (stripe_customer_id IS NOT NULL OR closed_at IS NOT NULL OR deleted_at IS NOT NULL)
);
-- What the daily job reads: the card pages still open, or taken up and not deleted yet.
CREATE INDEX card_checkouts_unfinished_idx ON card_checkouts (created_at)
  WHERE closed_at IS NULL AND deleted_at IS NULL AND stripe_unreachable_at IS NULL;

-- A saved card on a Stripe account this server can't use any more (saved with the shop's own key
-- before Stripe was connected, or the other way round, the other mode's key, or the shop took the
-- platform's access away) is removed here (removed_at: it can't book or be charged) but keeps its
-- Stripe ids, so the shop can find it and delete it in that account's Dashboard. This is when that
-- was found; it's cleared, with the ids, once the shop says it did.
ALTER TABLE saved_cards ADD COLUMN stripe_unreachable_at timestamptz NULL;
ALTER TABLE saved_cards
  ADD CONSTRAINT saved_cards_unreachable CHECK (stripe_unreachable_at IS NULL OR (removed_at IS NOT NULL AND stripe_customer_id IS NOT NULL));
CREATE INDEX saved_cards_unreachable_idx ON saved_cards (stripe_unreachable_at) WHERE stripe_unreachable_at IS NOT NULL;
