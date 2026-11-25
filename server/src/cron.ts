import { requireCron } from './auth.js';
import type { Deps } from './deps.js';
import { json } from './http.js';
import {
  anonymizeExpired,
  clearReceiptEmails,
  purgeSavedCards,
  purgeUnfinishedCheckouts,
  RETENTION_BUDGET_MS,
  retryCardsToDelete,
  type Anonymized,
  type CardPurge,
  type CardsToDeleteRetry,
  type CheckoutPurge,
} from './retention.js';
import type { Context } from './router.js';
import { addDays, localDate } from './time.js';

// GET /api/cron/daily (Vercel Cron, Authorization: Bearer CRON_SECRET).
// Idempotent: Vercel may deliver a run twice or skip one.
//
// Yelp: everything cached is purged on each run. A daily job runs ±59 minutes
// late on Hobby, so purging only rows older than N hours could leave a row that
// nobody read in the database for well over 24 hours; purging all of it bounds
// the worst case at one cron interval. The read path also drops rows past 24 h.
//
// Retention (retention.ts): card pages whose card was never saved here are
// deleted at Stripe (first: the Privacy Policy gives them only 2 days), clients'
// details older than 12 months are removed, in batches, saved cards that are due
// are deleted at Stripe, and what's on the shop's list of cards to delete in
// Stripe is tried again if the server's Stripe setup changed; for at most about
// 20 seconds in all (the function may run 30); what's left is done by the next
// run. Each step runs even when one before it fails (Vercel doesn't call a cron
// again after an error): the failure is logged, the answer is a 500 that names
// it, and the next run tries again.
//
// GET /api/cron/card-pages (Vercel Cron, 12 hours after the daily job): the card
// pages alone, once more. On Hobby each run comes anywhere within its scheduled
// hour, so two runs are at most 12 hours 59 minutes apart: a page is deleted
// within 35 hours of being made, or 47 when one run misses it, which keeps the
// Privacy Policy's 2 days (UNFINISHED_CHECKOUT_MARGIN_HOURS has the sums). Two
// daily cron jobs, rather than one hourly, since Hobby only allows daily ones
// (an hourly schedule fails the deployment there).

/** Runs one step of a cron job; a failure is logged and noted in `failed`, and the job goes on with `fallback`. */
async function step<T>(deps: Pick<Deps, 'log'>, failed: string[], name: string, fallback: T, run: () => Promise<T>): Promise<T> {
  try {
    return await run();
  } catch (error) {
    deps.log.error('A step of a cron job failed; the steps after it still ran', {
      step: name,
      error: error instanceof Error ? `${error.name}: ${error.message}` : String(error),
      code: typeof error === 'object' && error !== null && 'code' in error ? String(error.code) : undefined,
    });
    failed.push(name);
    return fallback;
  }
}

const NO_PAGES: CheckoutPurge = { deleted: 0, unreachable: 0, failed: 0 };

export async function dailyCron(ctx: Context): Promise<Response> {
  requireCron(ctx.request, ctx.deps.config);
  const started = Date.now();
  const budget = { stopAt: started + RETENTION_BUDGET_MS };
  const now = ctx.deps.now();
  const db = ctx.deps.db;
  const failed: string[] = [];
  const run = <T>(name: string, fallback: T, fn: () => Promise<T>) => step(ctx.deps, failed, name, fallback, fn);
  const unfinishedCardPages = await run('unfinishedCardPages', NO_PAGES, () => purgeUnfinishedCheckouts(ctx.deps, now, budget));
  const rateLimits = await run('rateLimits', 0, async () => {
    const result = await db.query('DELETE FROM rate_limits WHERE window_start < $1', [new Date(now.getTime() - 24 * 60 * 60 * 1000)]);
    return result.rowCount ?? 0;
  });
  const apiUsage = await run('apiUsage', 0, async () => {
    const result = await db.query('DELETE FROM api_usage WHERE day < $1', [addDays(localDate(now, ctx.deps.catalog.timeZone), -90)]);
    return result.rowCount ?? 0;
  });
  const yelpCache = await run('yelpCache', 0, async () => (await db.query('DELETE FROM yelp_cache')).rowCount ?? 0);
  const anonymized = await run<Anonymized>('anonymized', { appointments: 0, sales: 0, payments: 0 }, () => anonymizeExpired(db, now, budget));
  const receiptEmails = await run('receiptEmails', 0, () => clearReceiptEmails(db));
  const savedCards = await run<CardPurge>('savedCards', { deleted: 0, stillNeeded: 0, unreachable: 0, failed: 0 }, () => purgeSavedCards(ctx.deps, now, budget));
  const cardsToDelete = await run<CardsToDeleteRetry>('cardsToDelete', { deleted: 0, unreachable: 0, failed: 0 }, () =>
    retryCardsToDelete(ctx.deps, now, budget),
  );
  return json(
    {
      ok: failed.length === 0,
      ...(failed.length > 0 ? { failedSteps: failed } : {}),
      deleted: { rateLimits, apiUsage, yelpCache },
      anonymized: { ...anonymized, receiptEmails },
      savedCards,
      unfinishedCardPages,
      cardsToDelete,
    },
    failed.length > 0 ? 500 : 200,
  );
}

export async function cardPagesCron(ctx: Context): Promise<Response> {
  requireCron(ctx.request, ctx.deps.config);
  const budget = { stopAt: Date.now() + RETENTION_BUDGET_MS };
  const failed: string[] = [];
  const unfinishedCardPages = await step(ctx.deps, failed, 'unfinishedCardPages', NO_PAGES, () =>
    purgeUnfinishedCheckouts(ctx.deps, ctx.deps.now(), budget),
  );
  return json({ ok: failed.length === 0, ...(failed.length > 0 ? { failedSteps: failed } : {}), unfinishedCardPages }, failed.length > 0 ? 500 : 200);
}
