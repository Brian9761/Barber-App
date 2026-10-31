import { requireCron } from './auth.js';
import { json } from './http.js';
import type { Context } from './router.js';
import { addDays, localDate } from './time.js';

// GET /api/cron/daily (Vercel Cron, Authorization: Bearer CRON_SECRET).
// Idempotent: Vercel may deliver a run twice or skip one.
//
// Yelp: everything cached is purged on each run. A daily job runs ±59 minutes
// late on Hobby, so purging only rows older than N hours could leave a row that
// nobody read in the database for well over 24 hours; purging all of it bounds
// the worst case at one cron interval. The read path also drops rows past 24 h.

export async function dailyCron(ctx: Context): Promise<Response> {
  requireCron(ctx.request, ctx.deps.config);
  const now = ctx.deps.now();
  const db = ctx.deps.db;
  const rateLimits = await db.query('DELETE FROM rate_limits WHERE window_start < $1', [
    new Date(now.getTime() - 24 * 60 * 60 * 1000),
  ]);
  const apiUsage = await db.query('DELETE FROM api_usage WHERE day < $1', [
    addDays(localDate(now, ctx.deps.catalog.timeZone), -90),
  ]);
  const yelp = await db.query('DELETE FROM yelp_cache');
  return json({
    ok: true,
    deleted: { rateLimits: rateLimits.rowCount ?? 0, apiUsage: apiUsage.rowCount ?? 0, yelpCache: yelp.rowCount ?? 0 },
  });
}
