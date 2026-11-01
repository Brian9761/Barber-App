import { randomUUID } from 'node:crypto';
import { del, put } from '@vercel/blob';
import { attachDatabasePool, ipAddress } from '@vercel/functions';
import type pg from 'pg';
import Stripe from 'stripe';
import { newManageToken } from './auth.js';
import { loadCatalog } from './catalog.js';
import { configFromEnv } from './config.js';
import { createPool, poolDb, type Db } from './db.js';
import type { Deps, StripeClient } from './deps.js';

let pool: pg.Pool | undefined;

/** The shared pool, created on first use so routes without a database work without DATABASE_URL. */
function getPool(): pg.Pool {
  if (!pool) {
    const url = process.env.DATABASE_URL;
    if (!url) throw new Error('DATABASE_URL is not set');
    pool = createPool(url, { max: Number(process.env.PG_POOL_MAX) || 5 });
    // Release idle clients before Vercel suspends the instance.
    attachDatabasePool(pool);
  }
  return pool;
}

const lazyDb: Db = {
  query: (text, values) => poolDb(getPool()).query(text, values),
  transaction: (fn) => poolDb(getPool()).transaction(fn),
};

const stripeClients = new Map<string, StripeClient>();

/**
 * One JSON log line. Our message always stays `message`; a `message` among the
 * details (such as Stripe's own) becomes `detail`, instead of replacing it.
 */
export function logLine(level: 'error' | 'warn', message: string, details?: Record<string, unknown>): string {
  const { message: detail, ...rest } = details ?? {};
  return JSON.stringify({ level, message, ...rest, ...(detail === undefined ? {} : { detail }) });
}

export function productionDeps(env: NodeJS.ProcessEnv = process.env): Deps {
  return {
    db: lazyDb,
    config: configFromEnv(env),
    catalog: loadCatalog(),
    now: () => new Date(),
    uuid: randomUUID,
    manageToken: newManageToken,
    stripe(secretKey) {
      let client = stripeClients.get(secretKey);
      if (!client) {
        client = new Stripe(secretKey, { maxNetworkRetries: 1, timeout: 15_000, appInfo: { name: 'izzy-clipz-api' } });
        stripeClients.set(secretKey, client);
      }
      return client;
    },
    blob: {
      async put(pathname, body, options) {
        const result = await put(pathname, Buffer.from(body), {
          access: 'public',
          addRandomSuffix: true,
          contentType: options.contentType,
          cacheControlMaxAge: 60 * 60 * 24 * 30,
        });
        return { url: result.url };
      },
      async del(url) {
        await del(url);
      },
    },
    fetch: (input, init) => fetch(input, init),
    clientIp: (request) => ipAddress(request),
    log: {
      error: (message, details) => console.error(logLine('error', message, details)),
      warn: (message, details) => console.warn(logLine('warn', message, details)),
    },
  };
}
