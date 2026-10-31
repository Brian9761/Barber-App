-- The owner app sends an Idempotency-Key with each walk-in or phone booking
-- (POST /api/owner/appointments), so Book again after a lost answer gets the
-- appointment that went through instead of booking a second barber (or
-- slot_taken for the shop's own booking). One key, one appointment. Only the
-- SHA-256 is stored, like manage tokens; customer bookings have none (NULL).
ALTER TABLE appointments
  ADD COLUMN idempotency_key_hash text NULL CHECK (idempotency_key_hash ~ '^[0-9a-f]{64}$');

CREATE UNIQUE INDEX appointments_idempotency_key_hash_key
  ON appointments (idempotency_key_hash)
  WHERE idempotency_key_hash IS NOT NULL;
