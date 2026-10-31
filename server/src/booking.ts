import { hashManageToken } from './auth.js';
import { busyIntervals, gridStarts, isFree } from './availability.js';
import type { Catalog, Offering } from './catalog.js';
import { isOverlapConflict, type Queryable } from './db.js';
import type { Deps } from './deps.js';
import { ApiError } from './http.js';
import type { AppointmentRow } from './serialize.js';
import { addDays, addMinutes, dayBounds, localDate, wallClock, weekday } from './time.js';

/** Who a booking is for: one barber's menu item, or the service with whichever barber is free. */
export type Target =
  | { kind: 'offering'; offering: Offering }
  | { kind: 'any'; serviceId: string; offerings: readonly Offering[] };

export function resolveTarget(
  catalog: Catalog,
  input: { offeringId?: string | undefined; serviceId?: string | undefined; barberId?: string | undefined },
): Target {
  if (input.offeringId !== undefined) {
    const offering = catalog.offering(input.offeringId);
    if (!offering) throw new ApiError('invalid_request', "That service isn't on the menu any more. Pick another.");
    if (input.serviceId !== undefined && input.serviceId !== offering.serviceId) {
      throw new ApiError('invalid_request', "The service doesn't match the barber's menu item.");
    }
    if (input.barberId !== undefined && input.barberId !== offering.barberId) {
      throw new ApiError('invalid_request', "The barber doesn't match the menu item.");
    }
    return { kind: 'offering', offering };
  }
  if (input.serviceId === undefined) {
    throw new ApiError('invalid_request', 'Choose a service: send offeringId, or serviceId with barberId "any".');
  }
  if (input.barberId !== 'any') {
    throw new ApiError('invalid_request', 'To book a specific barber, send their offeringId. Otherwise use barberId "any".');
  }
  if (!catalog.service(input.serviceId)) {
    throw new ApiError('invalid_request', "That service isn't on the menu any more. Pick another.");
  }
  const offerings = catalog.firstAvailable(input.serviceId);
  if (!offerings) {
    throw new ApiError('invalid_request', 'This service needs a specific barber. Pick one to see their times.');
  }
  return { kind: 'any', serviceId: input.serviceId, offerings };
}

export function targetOfferings(target: Target): readonly Offering[] {
  return target.kind === 'offering' ? [target.offering] : target.offerings;
}

export type BookingMode = 'customer' | 'shop';

/**
 * Whether `start` can be booked for `offering`, ignoring other bookings.
 * Customers must pick one of the calendar's start times; the shop may book any
 * minute inside opening hours, including now (no lead time).
 */
export function checkStart(catalog: Catalog, offering: Offering, start: Date, now: Date, mode: BookingMode): ApiError | null {
  const zone = catalog.timeZone;
  const today = localDate(now, zone);
  const day = localDate(start, zone);
  const lastDay = addDays(today, catalog.windowDays);
  const tooFar = () =>
    new ApiError('too_far', `We take bookings up to ${catalog.windowDays} days ahead. Pick an earlier day.`);

  if (mode === 'customer') {
    if (start < now) return new ApiError('too_soon', 'That time has already passed. Pick another.');
    if (start < addMinutes(now, catalog.leadTimeMinutes)) {
      return new ApiError(
        'too_soon',
        `That's too soon. Pick a time at least ${catalog.leadTimeMinutes} minutes from now.`,
      );
    }
    if (day > lastDay) return tooFar();
    const hours = catalog.hours(weekday(day));
    if (!hours) return new ApiError('outside_hours', "We're closed that day. Pick another day.");
    const onGrid = gridStarts(catalog, day, offering.durationMinutes, now).some((s) => s.getTime() === start.getTime());
    if (!onGrid) return new ApiError('outside_hours', "That isn't one of our booking times. Pick a time from the list.");
    return null;
  }

  if (day < today) return new ApiError('too_soon', 'That day has already passed.');
  if (day > lastDay) return tooFar();
  const hours = catalog.hours(weekday(day));
  if (!hours) return new ApiError('outside_hours', 'The shop is closed that day.');
  const opens = wallClock(day, hours.opens, zone);
  const closes = wallClock(day, hours.closes, zone);
  if (!opens || !closes || start < opens || addMinutes(start, offering.durationMinutes) > closes) {
    return new ApiError('outside_hours', 'That time is outside opening hours.');
  }
  return null;
}

export interface NewAppointment {
  target: Target;
  start: Date;
  customer: { name: string; phone: string | null; email: string | null };
  note: string | null;
  mode: BookingMode;
  /** The customer's own manage token (`X-Manage-Token`), used instead of a new one. Ignored for the shop. */
  manageToken?: string | undefined;
  /** The owner app's `Idempotency-Key` for this booking; only its hash is stored. Shop bookings only. */
  idempotencyKey?: string | undefined;
}

export const MAX_UPCOMING_PER_PHONE = 3;

const slotTaken = () => new ApiError('slot_taken', 'Someone just booked that time. Pick another.');

/**
 * Books an appointment in one transaction. Nothing global is locked: the
 * barber rows are locked in id order (FOR UPDATE, like time off), so bookings
 * for the same barber take turns and time off can't slip in mid-booking. Time
 * off is checked, and the exclusion constraint decides overlaps (23P01 → 409).
 * Taking turns matters: two inserts of overlapping rows at the same moment can
 * each wait for the other inside the constraint's check, and Postgres aborts
 * one of them as a deadlock instead of answering "taken".
 * "Any barber" tries the free barbers with the fewest bookings that day first
 * (ties in team order), moving on if one gets taken in the meantime.
 */
export async function createAppointment(
  deps: Deps,
  input: NewAppointment,
): Promise<{ row: AppointmentRow; manageToken: string | null }> {
  const { catalog } = deps;
  const now = deps.now();

  const candidates: Offering[] = [];
  let firstProblem: ApiError | null = null;
  for (const offering of targetOfferings(input.target)) {
    const problem = checkStart(catalog, offering, input.start, now, input.mode);
    if (problem) firstProblem ??= problem;
    else candidates.push(offering);
  }
  if (candidates.length === 0) throw firstProblem ?? slotTaken();

  const manageToken = input.mode === 'customer' ? (input.manageToken ?? deps.manageToken()) : null;
  const id = deps.uuid();

  try {
    const row = await deps.db.transaction(async (tx) => {
      const barberIds = candidates.map((o) => o.barberId);
      const locked = await tx.query<{ id: string }>(
        'SELECT id FROM barbers WHERE id = ANY($1::text[]) AND active ORDER BY id FOR UPDATE',
        [barberIds],
      );
      const present = new Set(locked.rows.map((r) => r.id));
      const missing = barberIds.filter((b) => !present.has(b));
      if (missing.length > 0) {
        deps.log.error('Barbers missing from the database; run `npm run migrate` to seed them', { missing });
        if (present.size === 0) throw new Error('No bookable barbers in the database');
      }

      if (input.mode === 'customer' && input.customer.phone) {
        await enforcePhoneLimit(tx, input.customer.phone, now);
      }

      if (input.target.kind === 'offering') {
        const offering = candidates[0];
        if (!offering || !present.has(offering.barberId)) throw slotTaken();
        // Only time off is checked here; overlapping appointments are the constraint's job.
        if (await hasTimeOff(tx, offering.barberId, input.start, addMinutes(input.start, offering.durationMinutes))) {
          throw new ApiError('slot_taken', "That time isn't available any more. Pick another.");
        }
        return insertAppointment(tx, deps, id, offering, input, now, manageToken);
      }

      // Any barber: free ones first, fewest bookings that day, then team order.
      const maxEnd = addMinutes(input.start, Math.max(...candidates.map((o) => o.durationMinutes)));
      const busy = await busyIntervals(tx, barberIds, input.start, maxEnd);
      const free = candidates.filter(
        (o) => present.has(o.barberId) && isFree(busy, o.barberId, input.start, addMinutes(input.start, o.durationMinutes)),
      );
      if (free.length === 0) throw slotTaken();
      const counts = await bookingsThatDay(tx, catalog, free.map((o) => o.barberId), input.start);
      free.sort(
        (a, b) =>
          (counts.get(a.barberId) ?? 0) - (counts.get(b.barberId) ?? 0) ||
          catalog.barberRank(a.barberId) - catalog.barberRank(b.barberId),
      );
      for (const offering of free) {
        await tx.query('SAVEPOINT book_any');
        try {
          const inserted = await insertAppointment(tx, deps, id, offering, input, now, manageToken);
          await tx.query('RELEASE SAVEPOINT book_any');
          return inserted;
        } catch (error) {
          if (!isOverlapConflict(error)) throw error;
          await tx.query('ROLLBACK TO SAVEPOINT book_any');
        }
      }
      throw slotTaken();
    });
    return { row, manageToken };
  } catch (error) {
    if (isOverlapConflict(error)) throw slotTaken();
    throw error;
  }
}

async function enforcePhoneLimit(tx: Queryable, phone: string, now: Date): Promise<void> {
  // Serialize bookings for this number only, so two at once can't both squeeze under the limit.
  await tx.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 0))', [`phone:${phone}`]);
  const { rows } = await tx.query<{ n: number }>(
    `SELECT count(*)::int AS n FROM appointments
      WHERE customer_phone = $1 AND status = 'booked' AND start_at > $2`,
    [phone, now],
  );
  if ((rows[0]?.n ?? 0) >= MAX_UPCOMING_PER_PHONE) {
    throw new ApiError(
      'rate_limited',
      `This number already has ${MAX_UPCOMING_PER_PHONE} upcoming appointments. Cancel one, or call the shop to book more.`,
    );
  }
}

async function hasTimeOff(tx: Queryable, barberId: string, start: Date, end: Date): Promise<boolean> {
  const { rowCount } = await tx.query(
    `SELECT 1 FROM time_off
      WHERE (barber_id IS NULL OR barber_id = $1) AND start_at < $3 AND end_at > $2
      LIMIT 1`,
    [barberId, start, end],
  );
  return (rowCount ?? 0) > 0;
}

async function bookingsThatDay(tx: Queryable, catalog: Catalog, barberIds: string[], start: Date): Promise<Map<string, number>> {
  const { start: dayStart, end: dayEnd } = dayBounds(localDate(start, catalog.timeZone), catalog.timeZone);
  const { rows } = await tx.query<{ barber_id: string; n: number }>(
    `SELECT barber_id, count(*)::int AS n FROM appointments
      WHERE barber_id = ANY($1::text[])
        AND (status = 'booked' OR status = 'completed')
        AND start_at >= $2 AND start_at < $3
      GROUP BY barber_id`,
    [barberIds, dayStart, dayEnd],
  );
  return new Map(rows.map((r) => [r.barber_id, r.n]));
}

async function insertAppointment(
  tx: Queryable,
  deps: Deps,
  id: string,
  offering: Offering,
  input: NewAppointment,
  now: Date,
  manageToken: string | null,
): Promise<AppointmentRow> {
  const service = deps.catalog.service(offering.serviceId);
  const barber = deps.catalog.barber(offering.barberId);
  if (!service || !barber) throw new Error(`Catalog is missing ${offering.serviceId} or ${offering.barberId}`);
  const { rows } = await tx.query<AppointmentRow>(
    `INSERT INTO appointments (
       id, offering_id, service_id, barber_id, service_name, barber_name, price_label, price_cents, price_kind,
       start_at, end_at, status, cancelled_by, booked_by, customer_name, customer_phone, customer_email, note,
       manage_token_hash, any_barber, idempotency_key_hash, payment_status, created_at, updated_at)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, 'booked', NULL, $12, $13, $14, $15, $16, $17, $19, $20, 'unpaid', $18, $18)
     RETURNING *`,
    [
      id,
      offering.id,
      offering.serviceId,
      offering.barberId,
      service.name,
      barber.name,
      offering.priceLabel,
      offering.priceCents,
      offering.priceKind,
      input.start,
      addMinutes(input.start, offering.durationMinutes),
      input.mode,
      input.customer.name,
      input.customer.phone,
      input.customer.email,
      input.note,
      manageToken ? hashManageToken(manageToken) : null,
      now,
      input.target.kind === 'any',
      input.mode === 'shop' && input.idempotencyKey ? hashManageToken(input.idempotencyKey) : null,
    ],
  );
  const row = rows[0];
  if (!row) throw new Error('Insert returned no row');
  return row;
}
