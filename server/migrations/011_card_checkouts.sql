-- What the Privacy Policy promises about saved cards ("Saved cards"), kept by the database.
-- Additive only: every existing row stays valid, and the code already live keeps working on
-- this schema while the new code deploys.

-- Every "Add card" makes a Stripe Customer and a card page (a Checkout Session in setup mode)
-- before Stripe's page opens, and the card is only recorded in saved_cards when the app or the
-- website saves it afterwards (POST /api/cards). Each page is kept here from the moment it's made
-- until its card is saved (then the row goes: saved_cards has its ids from then on, and deletes
-- them from there). A card page that never gets that far (the page, the tab or the app closed
-- right after Stripe saved the card, say) stays, so the daily job can ask Stripe to delete its
-- card (if one was added) and its Customer. Stripe's ids only: nothing about the client.
--   abandoned_at           the daily job took it up because its card was never saved in time: from
--                          then on its card can't be saved any more
--   deleted_at             Stripe deleted its card and Customer (or had already deleted the
--                          Customer), or the shop deleted them in its Stripe Dashboard: nothing more
--                          to do (the row stays, so a late try can't save the card)
--   stripe_unreachable_at  it's on a Stripe account this server can't use any more: waiting for
--                          the shop to delete it in that account (Izzy Clipz Business and the
--                          website's Business settings list it)
--   stripe_unreachable_setup  how the server reached Stripe when it found that ('direct' or
--                          'connect', and the start of its key's SHA-256, never the key): the daily
--                          job tries it again once that changes (say the key is switched back)
-- The Customer's id goes once nothing more can be done with it.
CREATE TABLE card_checkouts (
  checkout_session_id      text PRIMARY KEY CHECK (checkout_session_id ~ '^cs_[A-Za-z0-9_]+$'),
  stripe_customer_id       text NULL CHECK (stripe_customer_id ~ '^cus_[A-Za-z0-9_]+$'),
  -- The connected account it's on (Stripe Connect); null when made with the shop's own key.
  stripe_account_id        text NULL CHECK (stripe_account_id ~ '^acct_[A-Za-z0-9]+$'),
  livemode                 boolean NOT NULL,
  created_at               timestamptz NOT NULL,
  abandoned_at             timestamptz NULL,
  deleted_at               timestamptz NULL,
  stripe_unreachable_at    timestamptz NULL,
  stripe_unreachable_setup text NULL CHECK (stripe_unreachable_setup ~ '^(direct|connect):[0-9a-f]{16}$'),
  CONSTRAINT card_checkouts_cleanup CHECK ((deleted_at IS NULL AND stripe_unreachable_at IS NULL) OR abandoned_at IS NOT NULL),
  CONSTRAINT card_checkouts_deleted_or_waiting CHECK (deleted_at IS NULL OR stripe_unreachable_at IS NULL),
  CONSTRAINT card_checkouts_customer CHECK (stripe_customer_id IS NOT NULL OR deleted_at IS NOT NULL),
  CONSTRAINT card_checkouts_unreachable CHECK (
    (stripe_unreachable_at IS NULL AND stripe_unreachable_setup IS NULL)
    OR (stripe_unreachable_at IS NOT NULL AND stripe_unreachable_setup IS NOT NULL)
  )
);
-- What the daily job reads: the card pages still open, or taken up and not deleted yet; and the
-- ones waiting for the shop.
CREATE INDEX card_checkouts_unfinished_idx ON card_checkouts (created_at)
  WHERE deleted_at IS NULL AND stripe_unreachable_at IS NULL;
CREATE INDEX card_checkouts_unreachable_idx ON card_checkouts (stripe_unreachable_at) WHERE stripe_unreachable_at IS NOT NULL;

-- A saved card on a Stripe account this server can't use any more (saved with the shop's own key
-- before Stripe was connected, or the other way round, the other mode's key, a key of another
-- Stripe account, or the shop took the platform's access away) is removed here (removed_at: it
-- can't book or be charged) but keeps its Stripe ids, so the shop can find it and delete it in
-- that account's Dashboard. stripe_unreachable_at is when that was found, and
-- stripe_unreachable_setup how the server reached Stripe then (as for card pages above: it's tried
-- again once that changes); both are cleared, with the ids, once it's deleted.
ALTER TABLE saved_cards
  ADD COLUMN stripe_unreachable_at timestamptz NULL,
  ADD COLUMN stripe_unreachable_setup text NULL CHECK (stripe_unreachable_setup ~ '^(direct|connect):[0-9a-f]{16}$'),
  ADD CONSTRAINT saved_cards_unreachable CHECK (
    (stripe_unreachable_at IS NULL AND stripe_unreachable_setup IS NULL)
    OR (stripe_unreachable_at IS NOT NULL AND stripe_unreachable_setup IS NOT NULL AND removed_at IS NOT NULL AND stripe_customer_id IS NOT NULL)
  );
CREATE INDEX saved_cards_unreachable_idx ON saved_cards (stripe_unreachable_at) WHERE stripe_unreachable_at IS NOT NULL;
