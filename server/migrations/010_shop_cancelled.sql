-- When the shop first cancelled a booking (docs/legal/cancellation-policy.md: the agreement for
-- a booking ends when the shop cancels it, and "If we cancel your appointment, there's never a
-- fee."). Reopening a booking clears cancelled_by, so without this a booking the shop cancelled
-- and then reopened could be marked a no-show, or cancelled late by the client, and charged. Set
-- the first time the shop cancels and never cleared: no fee can be charged once it's set, and the
-- booking no longer needs its card on file.
--
-- Bookings cancelled by the shop before this migration count from their last change. One the shop
-- cancelled and reopened before it can't be told apart any more (nothing kept that it was).
-- Additive only: every existing row stays valid, and the code already live keeps working on this
-- schema while the new code deploys (a booking it cancels for the shop is still cancelled_by
-- 'shop', which the new code reads as the shop's cancellation too).
ALTER TABLE appointments ADD COLUMN shop_cancelled_at timestamptz NULL;
UPDATE appointments SET shop_cancelled_at = updated_at WHERE status = 'cancelled' AND cancelled_by = 'shop';
