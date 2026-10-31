import { z } from 'zod';
import { dayRange } from './appointments.js';
import { requireOwner } from './auth.js';
import { ApiError, json, noContent, readJsonObject } from './http.js';
import type { Context } from './router.js';
import { timeOffJSON, type TimeOffRow } from './serialize.js';
import { dayBounds, floorToMinute } from './time.js';
import { instant, parse, UUID_RE } from './validation.js';

export const MAX_TIME_OFF_DAYS = 366;

// GET /api/owner/time-off?from=YYYY-MM-DD&to=YYYY-MM-DD → blocks that overlap those shop-local days
// (up to a year at a time, so the owner can see every upcoming block in one call).

export async function listTimeOff(ctx: Context): Promise<Response> {
  requireOwner(ctx.request, ctx.deps.config);
  const { from, to } = dayRange(ctx, MAX_TIME_OFF_DAYS);
  const zone = ctx.deps.catalog.timeZone;
  const { rows } = await ctx.deps.db.query<TimeOffRow>(
    `SELECT id, barber_id, start_at, end_at, reason FROM time_off
      WHERE start_at < $2 AND end_at > $1
      ORDER BY start_at, barber_id NULLS FIRST, id`,
    [dayBounds(from, zone).start, dayBounds(to, zone).end],
  );
  return json({ timeOff: rows.map(timeOffJSON) });
}

// POST /api/owner/time-off { barberId|null, start, end, reason? }

const timeOffBody = z.object({
  barberId: z.string({ error: 'barberId must be a barber id or null.' }).nullish(),
  start: instant,
  end: instant,
  reason: z
    .string({ error: 'The reason must be text.' })
    .nullish()
    .transform((v) => {
      const t = v?.trim() ?? '';
      return t === '' ? null : t;
    })
    .refine((v) => v === null || [...v].length <= 200, { error: 'Keep the reason to 200 characters or fewer.' }),
});

export async function postTimeOff(ctx: Context): Promise<Response> {
  requireOwner(ctx.request, ctx.deps.config);
  const body = parse(timeOffBody, await readJsonObject(ctx.request));
  const barberId = body.barberId ?? null;
  if (barberId !== null && !ctx.deps.catalog.barber(barberId)) {
    throw new ApiError('invalid_request', "That barber isn't on the team.");
  }
  const start = floorToMinute(body.start);
  const end = floorToMinute(body.end);
  if (end <= start) throw new ApiError('invalid_request', 'The end has to be after the start.');
  if (end.getTime() - start.getTime() > MAX_TIME_OFF_DAYS * 86_400_000) {
    throw new ApiError('invalid_request', `Block at most ${MAX_TIME_OFF_DAYS} days at a time.`);
  }
  const id = ctx.deps.uuid();
  const now = ctx.deps.now();
  const row = await ctx.deps.db.transaction(async (tx) => {
    // Wait for in-flight bookings for these barbers (they lock the same rows, in
    // the same id order), and make new ones wait for this block, so none can slip
    // in unseen.
    await tx.query(
      barberId === null
        ? 'SELECT id FROM barbers ORDER BY id FOR UPDATE'
        : 'SELECT id FROM barbers WHERE id = $1 FOR UPDATE',
      barberId === null ? [] : [barberId],
    );
    const { rows } = await tx.query<TimeOffRow>(
      `INSERT INTO time_off (id, barber_id, start_at, end_at, reason, created_at)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING id, barber_id, start_at, end_at, reason`,
      [id, barberId, start, end, body.reason, now],
    );
    return rows[0];
  });
  if (!row) throw new Error('Insert returned no row');
  return json({ timeOff: timeOffJSON(row) }, 201);
}

// DELETE /api/owner/time-off/:id → 204

export async function deleteTimeOff(ctx: Context): Promise<Response> {
  requireOwner(ctx.request, ctx.deps.config);
  const id = ctx.params.id ?? '';
  const notFound = () => new ApiError('not_found', "We couldn't find that time off. It may already be removed.");
  if (!UUID_RE.test(id)) throw notFound();
  const { rowCount } = await ctx.deps.db.query('DELETE FROM time_off WHERE id = $1', [id]);
  if (!rowCount) throw notFound();
  return noContent();
}
