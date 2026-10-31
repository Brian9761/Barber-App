-- The app may choose a booking's manage token itself (X-Manage-Token on
-- POST /api/appointments), so a retry after a lost answer can't book twice: the
-- token doubles as the booking's idempotency key. One token, one appointment.
-- Only the SHA-256 is stored, as before; shop bookings have none (NULL).
CREATE UNIQUE INDEX appointments_manage_token_hash_key
  ON appointments (manage_token_hash)
  WHERE manage_token_hash IS NOT NULL;

-- Whether it was booked for "any barber" (the server picked barber_id), so a
-- retry is only the same booking if it asks the same way.
ALTER TABLE appointments ADD COLUMN any_barber boolean NOT NULL DEFAULT false;
