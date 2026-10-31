import { createHash } from 'node:crypto';
import type { Queryable } from './db.js';

// Sliding-ish window limits in Postgres: counts live in 10-minute buckets, and a
// request is judged on the buckets that started within the last window.

const BUCKET_MINUTES = 10;

export interface Limit {
  max: number;
  windowMinutes: number;
}

/** Counts one hit for `key` and returns the total inside the window, including this one. */
export async function hit(db: Queryable, key: string, now: Date, limit: Limit): Promise<number> {
  const bucketMs = BUCKET_MINUTES * 60_000;
  const bucket = new Date(Math.floor(now.getTime() / bucketMs) * bucketMs);
  const windowStart = new Date(now.getTime() - limit.windowMinutes * 60_000);
  const { rows } = await db.query<{ total: number }>(
    `WITH bump AS (
       INSERT INTO rate_limits (key, window_start, count) VALUES ($1, $2, 1)
       ON CONFLICT (key, window_start) DO UPDATE SET count = rate_limits.count + 1
       RETURNING count
     )
     SELECT ((SELECT count FROM bump)
       + COALESCE((SELECT sum(count) FROM rate_limits
                    WHERE key = $1 AND window_start > $3 AND window_start <> $2), 0))::int AS total`,
    [key, bucket, windowStart],
  );
  return rows[0]?.total ?? 1;
}

/** Rate-limit keys never hold a raw IP address. */
export function ipKey(scope: string, ip: string | undefined): string {
  const digest = createHash('sha256').update(ip ?? 'unknown').digest('hex').slice(0, 32);
  return `${scope}:ip:${digest}`;
}
