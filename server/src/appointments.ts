import { z } from 'zod';
import { hashManageToken, isNewManageToken, isWellFormedManageToken, manageTokenMatches, requireOwner } from './auth.js';
import { availability } from './availability.js';
import { checkStart, createAppointment, resolveTarget, targetOfferings, type Target } from './booking.js';
import { EXCLUSION_VIOLATION, pgConstraint, pgErrorCode, UNIQUE_VIOLATION, type Queryable } from './db.js';
import { ApiError, json, readJsonObject } from './http.js';
import { hit, ipKey } from './ratelimit.js';
import type { Context } from './router.js';
import { appointmentJSON, STATUS_IN, type AppointmentRow, type AppointmentStatus } from './serialize.js';
import { dayBounds, daysBetween, floorToMinute, localDate } from './time.js';
import { calendarDate, email, instant, normalizeUSPhone, note, parse, personName, shortId, usPhone, UUID_RE } from './validation.js';

export const BOOKINGS_PER_IP_PER_HOUR = 5;
export const MAX_AVAILABILITY_DAYS = 31;
export const MAX_OWNER_RANGE_DAYS = 62;

const notFound = () => new ApiError('not_found', "We couldn't find that appointment.");

// GET /api/availability?offeringId=…|serviceId=…&barberId=any&from=YYYY-MM-DD&days=1..31

const availabilityQuery = z.object({
  offeringId: shortId.optional(),
  serviceId: shortId.optional(),
  barberId: shortId.optional(),
  from: calendarDate.optional(),
  days: z
    .string()
    .regex(/^\d{1,2}$/, { error: `days must be a whole number from 1 to ${MAX_AVAILABILITY_DAYS}.` })
    .transform(Number)
    .refine((n) => n >= 1 && n <= MAX_AVAILABILITY_DAYS, {
      error: `days must be a whole number from 1 to ${MAX_AVAILABILITY_DAYS}.`,
    })
    .optional(),
});

export async function getAvailability(ctx: Context): Promise<Response> {
  return availabilityResponse(ctx, {});
}

// GET /api/owner/availability: the same, without the lead time, so the owner can book a walk-in
// for the next slot that hasn't started yet.

export async function getOwnerAvailability(ctx: Context): Promise<Response> {
  requireOwner(ctx.request, ctx.deps.config);
  return availabilityResponse(ctx, { leadTimeMinutes: 0 });
}

async function availabilityResponse({ url, deps }: Context, options: { leadTimeMinutes?: number }): Promise<Response> {
  const query = parse(availabilityQuery, Object.fromEntries(url.searchParams));
  const target = resolveTarget(deps.catalog, query);
  const now = deps.now();
  const today = localDate(now, deps.catalog.timeZone);
  const from = query.from ?? today;
  // Nothing outside a year either way can have slots; this also keeps date math in 4-digit years.
  if (Math.abs(daysBetween(today, from)) > 366) {
    throw new ApiError('invalid_request', 'from must be within a year of today.');
  }
  const days = await availability(deps.db, deps.catalog, targetOfferings(target), from, query.days ?? 1, now, options);
  return json({ timeZone: deps.catalog.timeZone, days });
}

// POST /api/appointments

const customerBooking = z.object({
  offeringId: shortId.optional(),
  serviceId: shortId.optional(),
  barberId: shortId.optional(),
  start: instant,
  customer: z.object(
    { name: personName, phone: usPhone, email: email.optional() },
    { error: 'Add your name and mobile number.' },
  ),
  note: note.optional(),
});

function preflight(ctx: Context, target: Target, start: Date, mode: 'customer' | 'shop'): void {
  const now = ctx.deps.now();
  const problems = targetOfferings(target).map((o) => checkStart(ctx.deps.catalog, o, start, now, mode));
  if (problems.every((p) => p !== null)) throw problems[0] ?? new ApiError('slot_taken', 'Pick another time.');
}

type CustomerBooking = z.output<typeof customerBooking>;

const tokenUsed = () => new ApiError('invalid_request', 'That booking token was already used.');

/** The unique index on `appointments.manage_token_hash` (migrations/002). */
const MANAGE_TOKEN_INDEX = 'appointments_manage_token_hash_key';

/**
 * The app's own manage token from `X-Manage-Token`, if it sent one. It must be
 * exactly what the server would make (32 random bytes, base64url); anything
 * else, an empty header included, is a 400.
 */
function clientManageToken(request: Request): string | undefined {
  const header = request.headers.get('x-manage-token');
  if (header === null) return undefined;
  const token = header.trim();
  if (!isNewManageToken(token)) {
    throw new ApiError('invalid_request', 'X-Manage-Token must be 32 random bytes in base64url (43 characters).');
  }
  return token;
}

/**
 * Whether `row` is the booking `body` asks for: the same target, asked for the
 * same way (that offering, or that service with "any barber", whichever barber
 * the server picked), the same start and the same phone number. The name, email
 * and note aren't compared.
 */
function sameBooking(row: AppointmentRow, body: CustomerBooking): boolean {
  if (row.booked_by !== 'customer') return false;
  if (row.start_at.getTime() !== body.start.getTime()) return false;
  if (row.customer_phone !== body.customer.phone) return false;
  if (body.offeringId !== undefined) {
    return (
      !row.any_barber &&
      row.offering_id === body.offeringId &&
      (body.serviceId === undefined || body.serviceId === row.service_id) &&
      (body.barberId === undefined || body.barberId === row.barber_id)
    );
  }
  return row.any_barber && body.barberId === 'any' && body.serviceId === row.service_id;
}

/**
 * A retry of a booking that already went through (its answer was lost, or two
 * copies of the request crossed): 200 with the appointment as it is now (it may
 * have been cancelled since) and the same token. `null` if the token is new; a
 * 400 if it was used for a different booking.
 */
async function replay(db: Queryable, token: string, body: CustomerBooking): Promise<Response | null> {
  const { rows } = await db.query<AppointmentRow>('SELECT * FROM appointments WHERE manage_token_hash = $1', [
    hashManageToken(token),
  ]);
  const row = rows[0];
  if (!row) return null;
  if (!sameBooking(row, body)) throw tokenUsed();
  return json({ appointment: appointmentJSON(row), manageToken: token });
}

export async function postAppointment(ctx: Context): Promise<Response> {
  const { request, deps } = ctx;
  const token = clientManageToken(request);
  const body = parse(customerBooking, await readJsonObject(request));

  // A retry is answered before the time rules and the rate limit: it books
  // nothing, so it doesn't count as an attempt and works even after the lead
  // time has passed or the network has used up its attempts.
  if (token) {
    const replayed = await replay(deps.db, token, body);
    if (replayed) return replayed;
  }

  try {
    const target = resolveTarget(deps.catalog, body);
    preflight(ctx, target, body.start, 'customer');

    const hits = await hit(deps.db, ipKey('book', deps.clientIp(request)), deps.now(), {
      max: BOOKINGS_PER_IP_PER_HOUR,
      windowMinutes: 60,
    });
    if (hits > BOOKINGS_PER_IP_PER_HOUR) {
      throw new ApiError('rate_limited', 'Too many booking attempts from this network. Try again in an hour, or call the shop.', {
        headers: { 'retry-after': '3600' },
      });
    }

    const { row, manageToken } = await createAppointment(deps, {
      target,
      start: body.start,
      customer: { name: body.customer.name, phone: body.customer.phone, email: body.customer.email ?? null },
      note: body.note ?? null,
      mode: 'customer',
      manageToken: token,
    });
    return json({ appointment: appointmentJSON(row), manageToken }, 201);
  } catch (error) {
    // Another copy of this request with the same token may have booked it
    // meanwhile (its own slot then looks taken, or the token's unique index
    // stops this insert): answer like a retry.
    if (token) {
      const replayed = await replay(deps.db, token, body);
      if (replayed) return replayed;
      if (pgErrorCode(error) === UNIQUE_VIOLATION && pgConstraint(error) === MANAGE_TOKEN_INDEX) throw tokenUsed();
    }
    throw error;
  }
}

// GET /api/appointments/:id and POST /api/appointments/:id/cancel (X-Manage-Token)

async function loadWithToken(ctx: Context): Promise<AppointmentRow> {
  const token = ctx.request.headers.get('x-manage-token')?.trim();
  if (!token) throw new ApiError('unauthorized', 'This appointment needs its manage token.');
  const id = ctx.params.id ?? '';
  if (!UUID_RE.test(id) || !isWellFormedManageToken(token)) throw notFound();
  const { rows } = await ctx.deps.db.query<AppointmentRow>('SELECT * FROM appointments WHERE id = $1', [id]);
  const row = rows[0];
  // Same answer for "no such appointment" and "wrong token", so ids can't be probed.
  if (!row || !manageTokenMatches(token, row.manage_token_hash)) throw notFound();
  return row;
}

export async function getAppointment(ctx: Context): Promise<Response> {
  return json({ appointment: appointmentJSON(await loadWithToken(ctx)) });
}

export async function cancelAppointment(ctx: Context): Promise<Response> {
  const row = await loadWithToken(ctx);
  const now = ctx.deps.now();
  const { rows } = await ctx.deps.db.query<AppointmentRow>(
    `UPDATE appointments SET status = 'cancelled', cancelled_by = 'customer', updated_at = $2
      WHERE id = $1 AND status = 'booked' AND start_at > $2
      RETURNING *`,
    [row.id, now],
  );
  const updated = rows[0];
  if (updated) return json({ appointment: appointmentJSON(updated) });

  const { rows: current } = await ctx.deps.db.query<AppointmentRow>('SELECT * FROM appointments WHERE id = $1', [row.id]);
  const latest = current[0] ?? row;
  if (latest.status === 'cancelled') {
    throw new ApiError('not_cancellable', 'This appointment is already cancelled.');
  }
  if (latest.status !== 'booked') {
    throw new ApiError('not_cancellable', "This appointment can't be cancelled any more.");
  }
  throw new ApiError('not_cancellable', 'This appointment has already started. Call the shop if you need help.');
}

// Owner: GET/POST /api/owner/appointments, PATCH /api/owner/appointments/:id

const ownerRange = z.object({
  date: calendarDate.optional(),
  from: calendarDate.optional(),
  to: calendarDate.optional(),
});

/** `date`, or `from`&`to` (inclusive shop-local days, at most `maxDays`), defaulting to today. */
export function dayRange(ctx: Context, maxDays = MAX_OWNER_RANGE_DAYS): { from: string; to: string } {
  const q = parse(ownerRange, Object.fromEntries(ctx.url.searchParams));
  const today = localDate(ctx.deps.now(), ctx.deps.catalog.timeZone);
  let from: string;
  let to: string;
  if (q.date) {
    if (q.from || q.to) throw new ApiError('invalid_request', 'Send either date, or from and to.');
    from = to = q.date;
  } else if (q.from || q.to) {
    from = q.from ?? q.to ?? today;
    to = q.to ?? q.from ?? today;
  } else {
    from = to = today;
  }
  const span = daysBetween(from, to);
  if (span < 0) throw new ApiError('invalid_request', 'to must be on or after from.');
  if (span >= maxDays) {
    throw new ApiError('invalid_request', `Ask for at most ${maxDays} days at a time.`);
  }
  return { from, to };
}

export async function listOwnerAppointments(ctx: Context): Promise<Response> {
  requireOwner(ctx.request, ctx.deps.config);
  const { from, to } = dayRange(ctx);
  const zone = ctx.deps.catalog.timeZone;
  const { rows } = await ctx.deps.db.query<AppointmentRow>(
    `SELECT * FROM appointments WHERE start_at >= $1 AND start_at < $2 ORDER BY start_at, created_at, id`,
    [dayBounds(from, zone).start, dayBounds(to, zone).end],
  );
  return json({ appointments: rows.map(appointmentJSON) });
}

const ownerPhone = z
  .string({ error: 'Enter a US mobile number, or leave it empty.' })
  .nullish()
  .transform((v, ctx) => {
    const t = v?.trim() ?? '';
    if (t === '') return null;
    const phone = normalizeUSPhone(t);
    if (!phone) {
      ctx.addIssue({ code: 'custom', message: 'Enter a US mobile number, like (442) 341-3053, or leave it empty.' });
      return z.NEVER;
    }
    return phone;
  });

const ownerBooking = z.object({
  offeringId: shortId.optional(),
  serviceId: shortId.optional(),
  barberId: shortId.optional(),
  start: instant,
  customer: z.object({ name: personName, phone: ownerPhone, email: email.optional() }, { error: "Add the client's name." }),
  note: note.optional(),
});

export async function postOwnerAppointment(ctx: Context): Promise<Response> {
  requireOwner(ctx.request, ctx.deps.config);
  const body = parse(ownerBooking, await readJsonObject(ctx.request));
  const target = resolveTarget(ctx.deps.catalog, body);
  // The shop can book "now": any whole minute inside opening hours, no lead time.
  const start = floorToMinute(body.start);
  preflight(ctx, target, start, 'shop');
  const { row } = await createAppointment(ctx.deps, {
    target,
    start,
    customer: { name: body.customer.name, phone: body.customer.phone ?? null, email: body.customer.email ?? null },
    note: body.note ?? null,
    mode: 'shop',
  });
  return json({ appointment: appointmentJSON(row) }, 201);
}

const statusPatch = z.object({
  status: z.enum(['completed', 'noShow', 'cancelled', 'booked'], {
    error: 'status must be completed, noShow, cancelled or booked.',
  }),
});

export async function patchOwnerAppointment(ctx: Context): Promise<Response> {
  requireOwner(ctx.request, ctx.deps.config);
  const id = ctx.params.id ?? '';
  if (!UUID_RE.test(id)) throw notFound();
  const { status } = parse(statusPatch, await readJsonObject(ctx.request));
  const dbStatus = STATUS_IN[status as AppointmentStatus];
  try {
    const { rows } = await ctx.deps.db.query<AppointmentRow>(
      `UPDATE appointments
          SET status = $2,
              cancelled_by = CASE WHEN $2 = 'cancelled' THEN COALESCE(cancelled_by, 'shop') ELSE NULL END,
              updated_at = CASE WHEN status = $2 THEN updated_at ELSE $3 END
        WHERE id = $1
        RETURNING *`,
      [id, dbStatus, ctx.deps.now()],
    );
    const row = rows[0];
    if (!row) throw notFound();
    return json({ appointment: appointmentJSON(row) });
  } catch (error) {
    if (pgErrorCode(error) === EXCLUSION_VIOLATION) {
      throw new ApiError('slot_taken', 'Another appointment is booked at that time now, so this one can’t be restored.');
    }
    throw error;
  }
}
