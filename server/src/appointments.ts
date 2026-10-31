import { z } from 'zod';
import { isWellFormedManageToken, manageTokenMatches, requireOwner } from './auth.js';
import { availability } from './availability.js';
import { checkStart, createAppointment, resolveTarget, targetOfferings, type Target } from './booking.js';
import { EXCLUSION_VIOLATION, pgErrorCode } from './db.js';
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

export async function getAvailability({ url, deps }: Context): Promise<Response> {
  const query = parse(availabilityQuery, Object.fromEntries(url.searchParams));
  const target = resolveTarget(deps.catalog, query);
  const now = deps.now();
  const today = localDate(now, deps.catalog.timeZone);
  const from = query.from ?? today;
  // Nothing outside a year either way can have slots; this also keeps date math in 4-digit years.
  if (Math.abs(daysBetween(today, from)) > 366) {
    throw new ApiError('invalid_request', 'from must be within a year of today.');
  }
  const days = await availability(deps.db, deps.catalog, targetOfferings(target), from, query.days ?? 1, now);
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

export async function postAppointment(ctx: Context): Promise<Response> {
  const { request, deps } = ctx;
  const body = parse(customerBooking, await readJsonObject(request));
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
  });
  return json({ appointment: appointmentJSON(row), manageToken }, 201);
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

/** `date`, or `from`&`to` (inclusive shop-local days), defaulting to today. */
export function dayRange(ctx: Context): { from: string; to: string } {
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
  if (span >= MAX_OWNER_RANGE_DAYS) {
    throw new ApiError('invalid_request', `Ask for at most ${MAX_OWNER_RANGE_DAYS} days at a time.`);
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
