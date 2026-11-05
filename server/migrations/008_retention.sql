-- What the shop's legal documents promise (docs/legal/research.md §18), kept by the
-- database. Additive only: every existing row stays valid, and the code already live
-- keeps working on this schema while the new code deploys.

-- A booking with a card on file that the shop marked completed (or checked out) can't
-- become a no-show, even after it's reopened: the client came. Set the first time it's
-- completed and never cleared. Bookings completed before this migration count from
-- their last change.
ALTER TABLE appointments ADD COLUMN completed_at timestamptz NULL;
UPDATE appointments SET completed_at = updated_at WHERE status = 'completed';
