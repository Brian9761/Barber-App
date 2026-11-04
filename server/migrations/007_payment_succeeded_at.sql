-- When Stripe says each payment went through. That can be well after the payment
-- was made (a fee whose charge Stripe finished days later) or after the server
-- heard of it (a webhook Stripe sent again later, or an app that confirmed a
-- payment the next morning). A fee counts in the analytics on that day and its
-- appointment's chargedAt is that moment; a card sale is sold then. Additive
-- only: rows from before it keep NULL, and a fee without it counts on the day it
-- was made, as before, so the code already live keeps working on this schema.
ALTER TABLE payments ADD COLUMN succeeded_at timestamptz NULL;

-- The analytics read fees by the day they went through.
CREATE INDEX payments_fee_succeeded_idx ON payments ((COALESCE(succeeded_at, created_at)))
  WHERE kind IN ('no_show_fee', 'late_cancel_fee') AND status = 'succeeded';
